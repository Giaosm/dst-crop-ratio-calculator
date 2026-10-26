--种植计算器面板(纯客户端，挂在 HUD 控件层)
local GLOBAL_Class = GLOBAL.Class
local GLOBAL_Widget = GLOBAL.require("widgets/widget")
local GLOBAL_Image = GLOBAL.require("widgets/image")
local GLOBAL_ImageButton = GLOBAL.require("widgets/imagebutton")
local GLOBAL_Text = GLOBAL.require("widgets/text")

local panel = nil

local PLANT_DEFS = GLOBAL.require("prefabs/farm_plant_defs").PLANT_DEFS
local SEASONS = {--label 按钮文字；key 对应作物 good_seasons 的字段，"全部"为 nil
	{ label = "全部" },
	{ label = "春", key = "spring" },
	{ label = "夏", key = "summer" },
	{ label = "秋", key = "autumn" },
	{ label = "冬", key = "winter" },
}
local ROW_H = 45
local CONTENT_W = 700--分割线与两个视窗的共用宽度
local COLS = 10--每行作物图标数
local ICON = 40
local COL_W = CONTENT_W / COLS
local DIM = 0.55--未选中时的压暗系数
local MAX_PICKED = 3--最多同时选中的作物数
local REQ_FONT = 18--下半区"×N"与分隔符的字号
local REQ_ICON = 24--下半区图标尺寸
local REQ_GAP = 6--下半区图标与"×N"之间的间距
local REQ_SPLIT_GAP = 2--下半区与":"之间的间距(比例式紧排)
local REQ_COL_GAP = 30--下半区相邻"比组"之间的间距
local REQ_PER_ROW = 4--下半区每行并排几个"比组"(实际还会按内容区宽度再夹一次)
local REQ_MAX_CROPS = 3--一个比组里最多几个作物
local REQ_MAX_PLANTS = 10--一个比组的总株数上限(10 是自然上界，等于不限制)，nil 也不限制
local REQ_TEXT_COLOUR = { 0, 0, 0, 1 }--面板文字颜色(底板是浅色，统一用黑字)
local INFO_FONT = 18--标题下方悬停说明的字号
local INFO_COLOUR = { 0.6, 0.3, 0.3, 1 }--悬停说明的颜色(照参考模组的"柔和红"，纯红在浅底板上太刺眼)
local INFO_Y = 232--悬停说明的位置(在标题与第一条分割线之间，贴着分割线上沿)
local DEBUG_ICONS = 50--调试开关开启时补的"?"占位图标数量，用于测试滚动

--作物图标重映射：番茄与洋葱的标准图集里没图标，用活动图集里的同名图(照官方图鉴)
local ICON_REMAP = { tomato = "quagmire_tomato", onion = "quagmire_onion" }

--解析不到图标时用的占位图(官方图鉴的"?"图标)
local UNKNOWN_TEX, UNKNOWN_ATLAS = "unknown.tex", "images/scrapbook_icons3.xml"

--官方背包图集清单，也是自己探查时的顺序
local ICON_ATLASES = {
	"images/inventoryimages1.xml",
	"images/inventoryimages2.xml",
	"images/inventoryimages3.xml",
	"images/inventoryimages4.xml",
}
local OFFICIAL_ATLAS = {}
for _, a in ipairs(ICON_ATLASES) do
	OFFICIAL_ATLAS[a] = true
end

--找图标所在图集。先问官方接口(no_fallback=true)：
--* 官方图集要再验一次——inventoryItemAtlasLookup 是全局共享缓存，别处若用不带 no_fallback 的
--  方式查过同一张缺失图，缓存里存的是回退的 images4，不验就会拿到一张不含该图的图集(图标空白)
--* 模组通过 RegisterInventoryItemAtlas 注册的图集路径必须直接信任：AtlasContains 探不到模组图集，
--  拿它去验会把别的模组加的作物图标判成缺失，全掉成占位图
--* 全探不到时退回官方接口给的答案，至少不比改之前更差
local function FindIconAtlas(tex)
	local atlas = GetInventoryItemAtlas ~= nil and GetInventoryItemAtlas(tex, true) or nil
	if atlas ~= nil and (not OFFICIAL_ATLAS[atlas] or TheSim:AtlasContains(atlas, tex)) then
		return atlas
	end
	for _, a in ipairs(ICON_ATLASES) do
		if TheSim:AtlasContains(a, tex) then
			return a
		end
	end
	return atlas
end

--悬停说明的文字：养分净变化(带正负号)与家族数量。两者都是作物的固有属性，只算一次
local function MakePlantInfoText(plant)
	local d = Nutrient.GetDelta(plant)
	if d == nil then--不支持的作物已在 InitPlants 里滤掉，这里只是兜底
		return ""
	end
	local parts = {}
	for i = 1, 3 do
		parts[i] = string.format("%+d", d[i])
	end
	return string.format("养分：%s    家族：%d", table.concat(parts, "，"), PLANT_DEFS[plant].family_min_count or 0)
end

--作物列表、图标资源与悬停说明：进游戏后固定不变，只解析一次(面板会因 HUD 重建而多次构造)
local PLANTS, ICON_ASSETS, PLANT_INFO
local function InitPlants()
	if PLANTS then return end

	PLANTS = {}
	for name in pairs(PLANT_DEFS) do
		--跳过随机种子，以及其它模组新增却没写养分消耗的作物(否则算不出净变化)
		if name ~= "randomseed" and Nutrient.IsSupported(name) then
			table.insert(PLANTS, name)
		end
	end
	table.sort(PLANTS)

	ICON_ASSETS, PLANT_INFO = {}, {}
	for _, plant in ipairs(PLANTS) do
		local tex = (ICON_REMAP[plant] or plant) .. ".tex"
		local atlas = FindIconAtlas(tex)
		if not atlas then
			HelperDebug("作物图标缺失，改用占位图标：%s", plant)
			tex, atlas = UNKNOWN_TEX, UNKNOWN_ATLAS
		end
		ICON_ASSETS[plant] = { tex, atlas }
		PLANT_INFO[plant] = MakePlantInfoText(plant)
	end
end

--设置图标明暗(未选中压暗/选中原色)：悬停态也要设，否则点击后鼠标未移开时不会刷新
local function SetIconDim(icon, on)
	local v = on and 1 or DIM
	icon:SetImageNormalColour(v, v, v, 1)
	icon:SetImageFocusColour(v, v, v, 1)
end

--建一个作物图标按钮：四态同图靠色调区分选中，悬停等比放大
local function MakePlantIcon(tex, atlas, onclick)
	local icon = GLOBAL_ImageButton(atlas, tex, tex, tex, tex)
	icon:ForceImageSize(ICON, ICON)
	SetIconDim(icon, false)
	icon.move_on_click = false
	icon.ignore_standard_scaling = true
	icon:SetFocusScale(1.1, 1.1)
	icon:SetOnClick(onclick)
	return icon
end

--下半区一项"作物图标×N"：按文字实际宽度把 图标+数字 合成一块(原点在块中心)，位数变化也不会偏
local function MakeReqCell(plant, n)
	local cell = GLOBAL_Widget("ReqCell")

	local spec = ICON_ASSETS[plant]--spec = {tex, atlas}
	local icon = cell:AddChild(GLOBAL_Image(spec[2], spec[1]))
	icon:ScaleToSize(REQ_ICON, REQ_ICON)
	--图标小且可能因图集缺失显示成"?"，挂上名字，玩家悬停就能认出是哪个作物
	icon:SetHoverText(GLOBAL.STRINGS.NAMES[string.upper(plant)] or plant)

	local text = cell:AddChild(GLOBAL_Text(GLOBAL.NEWFONT, REQ_FONT))
	text:SetHAlign(GLOBAL.ANCHOR_LEFT)--左边缘固定，数字往右长
	text:SetColour(REQ_TEXT_COLOUR)
	text:SetString("×" .. n)
	local text_w = text:GetRegionSize()

	local total = REQ_ICON + REQ_GAP + text_w
	icon:SetPosition(-total / 2 + REQ_ICON / 2, 0, 0)
	text:SetPosition(-total / 2 + REQ_ICON + REQ_GAP, 0, 0)

	return cell, total--同时返回整项宽度，供外部排布
end

--下半区一个"比组"：crops 与 counts 一一对应，用":"串成一行，整组居中于自身原点
local function MakeRatioGroup(crops, counts)
	local group = GLOBAL_Widget("RatioGroup")
	local parts, sum_w = {}, 0
	local function push(widget, w)
		table.insert(parts, { widget = widget, w = w })
		sum_w = sum_w + w
	end

	for i, plant in ipairs(crops) do
		if i > 1 then--比例分隔符
			local colon = group:AddChild(GLOBAL_Text(GLOBAL.NEWFONT, REQ_FONT))
			colon:SetColour(REQ_TEXT_COLOUR)
			colon:SetString(":")
			push(colon, colon:GetRegionSize())
		end
		local cell, w = MakeReqCell(plant, counts[i])
		group:AddChild(cell)
		push(cell, w)
	end

	--按各段实际宽度等距排开，整组居中于自身原点
	local row_w = sum_w + REQ_SPLIT_GAP * (#parts - 1)
	local x = -row_w / 2
	for _, p in ipairs(parts) do
		p.widget:SetPosition(x + p.w / 2, 0, 0)
		x = x + p.w + REQ_SPLIT_GAP
	end

	return group, row_w--同时返回整组宽度，供外部排布
end

--可滚动视窗：透明命中层 + 边框 + 裁剪 + 内容层 + 滚动条
local PlantCalcView = GLOBAL_Class(GLOBAL_Widget, function(self, w, h, row_h)
	GLOBAL_Widget._ctor(self, "PlantCalcView")
	self.view_h = h
	self.row_h = row_h
	self.content_h = 0
	self.scroll = 0

	local hit = self:AddChild(GLOBAL_Image("images/ui.xml", "blank.tex"))--透明命中层：不带背景色，只提供鼠标焦点区域
	hit:ScaleToSize(w, h)

	if HelperConfig.view_border then
		for _, line in ipairs({
			{ 0, h / 2, w, 2 }, { 0, -h / 2, w, 2 },
			{ -w / 2, 0, 2, h }, { w / 2, 0, 2, h },
		}) do
			local l = self:AddChild(GLOBAL_Image("images/global.xml", "square.tex"))
			l:ScaleToSize(line[3], line[4])
			l:SetPosition(line[1], line[2])
			l:SetTint(0.55, 0.45, 0.3, 0.9)
		end
	end

	local pad = HelperConfig.view_border and 1 or 0--有边框时外扩，让边界上的线完整显示
	self:SetScissor(-w / 2 - pad, -h / 2 - pad, w + pad * 2, h + pad * 2)
	self.content = self:AddChild(GLOBAL_Widget("content"))

	self.bar = self:AddChild(GLOBAL_Widget("scrollbar"))
	self.bar:SetPosition(w / 2 - 9, 0)
	self.bar:AddChild(GLOBAL_Image("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_bar.tex")):ScaleToSize(2, h)
	self.handle = self.bar:AddChild(GLOBAL_Image("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex"))
	self.handle:ScaleToSize(6, 8)
	self.bar:Hide()

	self:_Apply()
end)

--内容总行数，决定滚动范围与滚动条显隐
function PlantCalcView:SetContentRows(n)
	self.content_h = n * self.row_h
	self.scroll = math.min(self.scroll, math.max(0, self.content_h - self.view_h))
	self:_Apply()
end

function PlantCalcView:Scroll(dir)
	local max_scroll = math.max(0, self.content_h - self.view_h)
	if max_scroll <= 0 then return end
	self.scroll = math.clamp(self.scroll + dir * self.row_h, 0, max_scroll)
	self:_Apply()
end

function PlantCalcView:_Apply()
	self.content:SetPosition(0, self.view_h / 2 - self.row_h / 2 + self.scroll)

	local max_scroll = self.content_h - self.view_h
	if max_scroll <= 0 then
		self.bar:Hide()
		return
	end
	self.bar:Show()
	local range = self.view_h - 8
	self.handle:SetPosition(0, range / 2 - (self.scroll / max_scroll) * range)
end

function PlantCalcView:OnControl(control, down)
	if PlantCalcView._base.OnControl(self, control, down) then return true end
	if not down then return false end
	if control == GLOBAL.CONTROL_SCROLLBACK then
		self:Scroll(-1)
		return true
	elseif control == GLOBAL.CONTROL_SCROLLFWD then
		self:Scroll(1)
		return true
	end
	return false
end

local PlantCalcPanel = GLOBAL_Class(GLOBAL_Widget, function(self)
	GLOBAL_Widget._ctor(self, "PlantCalcPanel")

	self.root = self:AddChild(GLOBAL_Widget("ROOT"))
	self.root:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
	self.root:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
	self.root:SetScaleMode(GLOBAL.SCALEMODE_PROPORTIONAL)

	local bg = self.root:AddChild(GLOBAL_Image("images/skilltree.xml", "wilson_background_text.tex"))
	bg:ScaleToSize(800, 700)

	local title = self.root:AddChild(GLOBAL_Text(GLOBAL.BODYTEXTFONT, 34))
	title:SetString("简易种植计算器")
	title:SetPosition(0, 250, 0)
	title:SetColour(1, 0.85, 0.3, 1)

	--标题与第一条分割线之间的一行说明：鼠标停在上半区作物上时显示它的养分与家族数量
	self.info_text = self.root:AddChild(GLOBAL_Text(GLOBAL.NEWFONT, INFO_FONT))
	self.info_text:SetString("")
	self.info_text:SetColour(INFO_COLOUR)
	self.info_text:SetPosition(0, INFO_Y, 0)

	local divider = self.root:AddChild(GLOBAL_Image("images/frontend_redux.xml", "achievements_wide_divider_top.tex"))
	divider:SetPosition(0, 225, 0)
	divider:ScaleToSize(CONTENT_W, 15)

	--季节筛选按钮：横向平均排列、整体居中
	local BTN_W, BTN_H, BTN_GAP, BTN_Y = 120, 40, 20, 190
	local start_x = -(#SEASONS - 1) * (BTN_W + BTN_GAP) / 2
	self.season_btns = {}
	for i, s in ipairs(SEASONS) do
		local btn = self.root:AddChild(GLOBAL_ImageButton(
			"images/global_redux.xml",
			"button_carny_long_normal.tex",
			"button_carny_long_hover.tex",
			"button_carny_long_disabled.tex",
			"button_carny_long_down.tex",
			"button_carny_long_normal.tex"--选中态沿用普通纹理，靠色调区分，避开 hover 纹理的四角装饰
		))
		btn:ForceImageSize(BTN_W, BTN_H)
		btn:SetText(s.label)
		btn:SetFont(GLOBAL.NEWFONT)
		btn:SetTextSize(20)
		btn:SetImageNormalColour(DIM, DIM, DIM, 1)--未选中压暗
		btn:SetImageSelectedColour(1, 1, 1, 1)--选中恢复原色
		btn:SetOnClick(function() self:SetSeason(i) end)
		btn:SetPosition(start_x + (i - 1) * (BTN_W + BTN_GAP), BTN_Y, 0)
		self.season_btns[i] = btn
	end

	--两个滚动视窗(按钮下方 5 处起)：上 6 行(底部收 20)、下 4 行，两框边框重合无间距
	local top_h = 6 * ROW_H - 20
	local view_y = BTN_Y - BTN_H / 2 - 5
	self.view_top = self.root:AddChild(PlantCalcView(CONTENT_W, top_h, ROW_H))
	self.view_top:SetPosition(0, view_y - top_h / 2)
	self.view_bottom = self.root:AddChild(PlantCalcView(CONTENT_W, 4 * ROW_H, ROW_H))
	self.view_bottom:SetPosition(0, view_y - top_h - 4 * ROW_H / 2)

	--两框交界处的细分隔线
	local split = self.root:AddChild(GLOBAL_Image("images/global.xml", "square.tex"))
	split:ScaleToSize(CONTENT_W, 2)
	split:SetPosition(0, view_y - top_h, 0)
	split:SetTint(0.55, 0.45, 0.3, 0.9)

	--上半区以图标展示作物，点击切换选中；位置统一由 SetSeason 排布
	InitPlants()
	self.plant_icons = {}
	self.picked = {}
	for _, plant in ipairs(PLANTS) do
		local spec = ICON_ASSETS[plant]
		local icon = MakePlantIcon(spec[1], spec[2], function() self:TogglePlant(plant) end)
		icon:SetHoverText(GLOBAL.STRINGS.NAMES[string.upper(plant)] or plant)
		icon:SetOnGainFocus(function() self:ShowPlantInfo(plant) end)
		icon:SetOnLoseFocus(function() self:HidePlantInfo() end)
		self.view_top.content:AddChild(icon)
		self.plant_icons[plant] = icon
	end

	--调试开关开启时：补一批"?"占位图标用于测试滚动，不参与选中
	self.debug_icons = {}
	if HelperConfig.debug then
		for _ = 1, DEBUG_ICONS do
			local icon = MakePlantIcon(UNKNOWN_TEX, UNKNOWN_ATLAS)
			self.view_top.content:AddChild(icon)
			table.insert(self.debug_icons, icon)
		end
	end

	--下半区内容由 SetSeason → FilterPlants → RefreshGroups 生成
	self:SetSeason(1)
end)

--鼠标停到作物图标上：显示它的养分与家族数量
function PlantCalcPanel:ShowPlantInfo(plant)
	self.info_text:SetString(PLANT_INFO[plant])
end

--鼠标离开图标：确认没有别的作物还带着焦点，才清空说明行。
--(悬停到新图标时，新图标先获焦、旧图标后失焦，这里直接清会把刚写上的内容当场抹掉)
function PlantCalcPanel:HidePlantInfo()
	for _, icon in pairs(self.plant_icons) do
		if icon.focus then return end
	end
	self.info_text:SetString("")
end

--切换选中的季节：选中态用 ImageButton 原生 Selected 状态，自带高亮且不可重复点击
function PlantCalcPanel:SetSeason(index)
	self.season = index
	for i, btn in ipairs(self.season_btns) do
		if i == index then
			btn:Select()
		else
			btn:Unselect()
		end
	end
	self:FilterPlants()
end

--清空已选并重排作物图标：非应季的隐藏、应季的紧凑排列。一次遍历同时完成色调复位与排布
function PlantCalcPanel:FilterPlants()
	self.picked = {}
	local key = SEASONS[self.season].key
	local count = 0
	local function place(icon)
		icon:Show()
		icon:SetPosition(-CONTENT_W / 2 + COL_W / 2 + (count % COLS) * COL_W, -math.floor(count / COLS) * ROW_H)
		count = count + 1
	end

	for _, plant in ipairs(PLANTS) do
		local icon = self.plant_icons[plant]
		if icon then
			SetIconDim(icon, false)
			if Nutrient.IsInSeason(plant, key) then
				place(icon)
			else
				icon:Hide()
			end
		end
	end

	--调试占位图标始终显示，接在作物后面
	for _, icon in ipairs(self.debug_icons) do
		place(icon)
	end

	self.view_top:SetContentRows(math.ceil(count / COLS))
	self:RefreshGroups()--换季会清空已选，下半区跟着重算
end

--已选作物数量
local function CountPicked(picked)
	local n = 0
	for _ in pairs(picked) do n = n + 1 end
	return n
end

--点击作物图标：选中恢复原色，再次点击取消选中；最多同时选 MAX_PICKED 种，满了给无效音
function PlantCalcPanel:TogglePlant(plant)
	if self.picked[plant] then
		self.picked[plant] = nil
	else
		if CountPicked(self.picked) >= MAX_PICKED then
			TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_negative")
			return
		end
		self.picked[plant] = true
	end
	SetIconDim(self.plant_icons[plant], self.picked[plant])
	self:RefreshGroups()--选中变了，下半区的比组跟着重算
end

--重建下半区：以选中作物为锚，在当前季节的候选池里找所有能让养分归零的比组
function PlantCalcPanel:RefreshGroups()
	local content = self.view_bottom.content
	content:KillAllChildren()

	--选中作物按 PLANTS 的既定顺序取，保证比组里选中的那几个顺序稳定
	local selected = {}
	for _, plant in ipairs(PLANTS) do
		if self.picked[plant] then
			table.insert(selected, plant)
		end
	end
	if #selected == 0 then--没选作物就没有比组
		self.view_bottom:SetContentRows(0)
		return
	end

	local season_key = SEASONS[self.season].key

	--候选池：当季应季的作物，去掉已选中的(选中作物会由 FindGroups 自己放在组首)
	local pool = {}
	for _, plant in ipairs(Nutrient.FilterBySeason(PLANTS, season_key)) do
		if not self.picked[plant] then
			table.insert(pool, plant)
		end
	end

	local groups = Nutrient.FindGroups(selected, pool, REQ_MAX_CROPS, REQ_MAX_PLANTS)
	if season_key == nil then
		--"全部"下也要滤掉组内作物季节无交集的组合：它们数学上成立，但没有任何季节能同时种出来
		local kept = {}
		for _, g in ipairs(groups) do
			if Nutrient.HasCommonSeason(g.crops) then
				table.insert(kept, g)
			end
		end
		groups = kept
	end

	--一组都凑不出来时给一行提示，否则下半区一片空白，玩家分不清是"无解"还是"没选中"
	if #groups == 0 then
		local tip = content:AddChild(GLOBAL_Text(GLOBAL.NEWFONT, REQ_FONT))
		tip:SetString("当前选中的作物没有互补配比")
		tip:SetColour(REQ_TEXT_COLOUR)
		tip:SetPosition(0, 0, 0)
		self.view_bottom:SetContentRows(1)
		return
	end

	--先建出来量宽度：槽宽按最宽的比组定，这样窄的组也占同样宽的位，行内排布不漂移
	local built, max_w = {}, 0
	for _, g in ipairs(groups) do
		local group, w = MakeRatioGroup(g.crops, g.counts)
		table.insert(built, { group = group, w = w })
		max_w = math.max(max_w, w)
	end

	--按槽宽夹出每行放得下几个：放不下就减，绝不让比组顶出内容区被裁
	local slot_w = max_w + REQ_COL_GAP
	local per_row = math.min(REQ_PER_ROW, math.max(1, math.floor(CONTENT_W / slot_w)))
	local row_left = -slot_w * per_row / 2--整行居中

	for i, item in ipairs(built) do
		local col = (i - 1) % per_row
		local row = math.floor((i - 1) / per_row)
		item.group:SetPosition(row_left + slot_w * col + item.w / 2, -row * ROW_H, 0)
		content:AddChild(item.group)
	end

	self.view_bottom:SetContentRows(math.ceil(#built / per_row))
end

--鼠标是否停在任一个滚动视窗上
function PlantCalcPanel:IsHoveringViews()
	return self.view_top.focus or self.view_bottom.focus
end

--隐藏不会自动释放焦点：递归清掉子树里的焦点。
--(Widget:ClearFocus 只在自己持有焦点时才往下递归，所以要先找到真正持焦点的那个再清)
local function ClearFocusTree(widget)
	if widget.focus then
		widget:ClearFocus()
		return
	end
	for _, child in pairs(widget.children) do
		ClearFocusTree(child)
	end
end

function PlantCalcPanel:Close()
	--两个视窗都清：漏掉的焦点会让重开面板后相机缩放的屏蔽一直生效(说明行也跟着失焦清空)
	ClearFocusTree(self.view_top)
	ClearFocusTree(self.view_bottom)
	self:Hide()
end

--ESC关闭；返回 true 吞掉控制，避免点击穿透到游戏
function PlantCalcPanel:OnControl(control, down)
	if PlantCalcPanel._base.OnControl(self, control, down) then return true end
	if not down and control == GLOBAL.CONTROL_CANCEL then
		self:Close()
	end
	return true
end

--HUD 重建时跟着重建
AddClassPostConstruct("widgets/controls", function(self)
	panel = (self.bottomright_root or self):AddChild(PlantCalcPanel())
	panel:Hide()
end)

--当前是否不该响应快捷键：聊天/控制台/暂停菜单/模组设置等任何浮层打开时都算。
--游戏内正常画面下 GetActiveScreen() 返回的就是 ThePlayer.HUD(见 playerhud 的用法)，只有它不是浮层
local function IsTypingActive()
	local FE = TheFrontEnd
	if FE == nil then return false end

	local screen = FE:GetActiveScreen()
	if screen ~= nil and (ThePlayer == nil or screen ~= ThePlayer.HUD) then
		return true
	end
	if FE.forceProcessText == true and FE.textProcessorWidget ~= nil then return true end

	--兜底：焦点控件自己或它的祖先带着 editing 标记(内嵌在 HUD 里的输入框)
	local w = FE:GetFocusWidget()
	while w ~= nil do
		if w.editing == true then return true end
		w = w.parent
	end
	return false
end

local function TogglePlantCalcUI()
	if not (ThePlayer and ThePlayer.HUD) then return end
	if IsTypingActive() then return end
	if panel == nil or not panel.inst:IsValid() then return end
	if panel:IsVisible() then
		panel:Close()
	else
		panel:Show()
	end
end

--鼠标停在滚动视窗上时屏蔽相机缩放：滚轮只滚列表，视角不动。
--相机缩放由 PlayerController 每帧轮询触发、不走 UI 事件链，只能在相机方法上拦
AddClassPostConstruct("cameras/followcamera", function(self)
	local _ZoomIn, _ZoomOut = self.ZoomIn, self.ZoomOut
	local function locked()
		return panel ~= nil and panel.inst:IsValid() and panel:IsVisible() and panel:IsHoveringViews()
	end
	self.ZoomIn = function(cam, ...)
		if locked() then return end
		return _ZoomIn(cam, ...)
	end
	self.ZoomOut = function(cam, ...)
		if locked() then return end
		return _ZoomOut(cam, ...)
	end
end)

--用 KeyUp：长按不会重复触发
if HelperConfig.key ~= nil then
	TheInput:AddKeyUpHandler(HelperConfig.key, function()
		TogglePlantCalcUI()
	end)
end
