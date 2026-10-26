--种植养分计算(纯算法)：每株作物的净变化是固定整数向量(取自 farming_manager.lua 的 CycleNutrientsAtPoint，三数之和恒为 0)，养分互补即求 Σ x·Δ = 0 的最小正整数解；分量顺序 1 催长剂 2 堆肥 3 粪肥

local PLANT_DEFS = GLOBAL.require("prefabs/farm_plant_defs").PLANT_DEFS

local MAX_CROPS = 3--比组内作物数上限(含选中作物)，同时也是求解器能处理的作物数上限

Nutrient = {}

------------ 基础工具 ------------

local function Gcd(a, b)
	a, b = math.abs(a), math.abs(b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

local function Sum(counts)
	local n = 0
	for _, v in ipairs(counts) do
		n = n + v
	end
	return n
end

--最简整数比：各项除以最大公约数
local function Simplify(counts)
	local g = 0
	for _, v in ipairs(counts) do
		g = Gcd(g, v)
	end
	if g > 1 then
		for i, v in ipairs(counts) do
			counts[i] = v / g
		end
	end
	return counts
end

------------ 净变化向量 ------------

local deltas = {}--plant -> {催长剂, 堆肥, 粪肥}

--消耗向量是否可用于计算：三个数值分量、且至少消耗一种养分。
--别的模组可能往 PLANT_DEFS 里加自定义作物，未必写这一项；缺字段的作物直接跳过，不能让整个面板报错
function Nutrient.IsSupported(plant)
	local def = PLANT_DEFS[plant]
	local consume = def ~= nil and def.nutrient_consumption or nil
	if consume == nil then
		return false
	end

	local total = 0
	for i = 1, 3 do
		local v = consume[i]
		if type(v) ~= "number" then
			return false
		end
		total = total + math.abs(v)
	end
	return total > 0--全 0(如随机种子)没有净变化可言
end

--某作物的净变化，三数之和恒为 0；不支持的作物返回 nil
local function GetDelta(plant)
	local d = deltas[plant]
	if d == nil then
		if not Nutrient.IsSupported(plant) then
			return nil
		end
		local consume = PLANT_DEFS[plant].nutrient_consumption

		local total, back_count = 0, 0
		for i = 1, 3 do
			if consume[i] == 0 then
				back_count = back_count + 1
			else
				total = total + consume[i]
			end
		end

		local back = back_count > 0 and math.floor(total / back_count) or 0
		d = {}
		for i = 1, 3 do
			d[i] = consume[i] == 0 and back or -consume[i]
		end
		deltas[plant] = d
	end
	return d
end

--某作物的净养分变化(三数之和恒为 0)，返回副本，避免外部改到内部缓存；不支持的作物返回 nil
function Nutrient.GetDelta(plant)
	local d = GetDelta(plant)
	return d ~= nil and { d[1], d[2], d[3] } or nil
end

--一组作物是否存在共同的应季季节(至少一个)。
--没有共同季节的组合(如 榴莲{春} 配 辣椒{秋,夏})数学上能互补，但实际永远种不到一起
function Nutrient.HasCommonSeason(crops)
	local common = nil
	for _, plant in ipairs(crops) do
		local seasons = PLANT_DEFS[plant].good_seasons
		if seasons == nil then
			return false
		end

		if common == nil then
			common = {}
			for s in pairs(seasons) do
				common[s] = true
			end
		else
			local left = false
			for s in pairs(common) do
				if seasons[s] then
					left = true
				else
					common[s] = nil
				end
			end
			if not left then
				return false
			end
		end
	end
	return common ~= nil and next(common) ~= nil
end

--某作物在某季节是否应季；season 传 nil 表示不筛(全部视为应季)
function Nutrient.IsInSeason(plant, season)
	if season == nil then
		return true
	end
	local seasons = PLANT_DEFS[plant].good_seasons
	return seasons ~= nil and seasons[season] ~= nil
end

--按季节筛出可用作物；season 传 nil 表示不筛(返回全部)
function Nutrient.FilterBySeason(plants, season)
	local out = {}
	for _, plant in ipairs(plants) do
		if Nutrient.IsInSeason(plant, season) then
			table.insert(out, plant)
		end
	end
	return out
end

------------ 比组求解 ------------

--校验一组数量确实让养分归零
local function IsBalanced(crops, counts)
	local net = { 0, 0, 0 }
	for i, plant in ipairs(crops) do
		local d = GetDelta(plant)
		if d == nil then
			return false
		end
		for k = 1, 3 do
			net[k] = net[k] + counts[i] * d[k]
		end
	end
	return net[1] == 0 and net[2] == 0 and net[3] == 0
end

--两作物：只有两个 Δ 反向平行才有解
local function Solve2(a, b)
	local ax, ay = a[1], a[2]
	local bx, by = b[1], b[2]
	if ax * by - ay * bx ~= 0 then
		return nil--不平行
	end

	local x, y
	if ax ~= 0 then
		local g = Gcd(ax, bx)
		x, y = math.abs(bx) / g, math.abs(ax) / g
	elseif ay ~= 0 then
		local g = Gcd(ay, by)
		x, y = math.abs(by) / g, math.abs(ay) / g
	end
	if x == nil or x <= 0 or y <= 0 then
		return nil
	end
	return { x, y }
end

--退化情形：三个 Δ 两两平行(胡萝卜与南瓜的净变化就完全相同)时两个方程只剩一个、解集是二维的，改为枚举两个解出第三个；系数绝对值 ≤ 8，最简解远在枚举上限内
local PARALLEL_LIMIT = 32--每个数量的枚举上限
local function Solve3Parallel(r1, r2)
	local c = (r1[1] ~= 0 or r1[2] ~= 0 or r1[3] ~= 0) and r1 or r2--取非零的那一行当系数

	local pos, neg = false, false
	for i = 1, 3 do
		if c[i] > 0 then pos = true
		elseif c[i] < 0 then neg = true end
	end
	if not (pos and neg) then
		return nil--同号，凑不出 0
	end

	local p = c[1] ~= 0 and 1 or (c[2] ~= 0 and 2 or 3)--拿非零的那一项当被解出的
	local i = p == 1 and 2 or 1
	local j = p == 3 and 2 or 3

	local best, best_sum
	for x = 1, PARALLEL_LIMIT do
		for y = 1, PARALLEL_LIMIT do
			local rest = -(c[i] * x + c[j] * y)
			if rest % c[p] == 0 then
				local z = rest / c[p]
				local sum = x + y + z
				if z >= 1 and sum < (best_sum or math.huge) then
					local counts = { 0, 0, 0 }
					counts[i], counts[j], counts[p] = x, y, z
					best, best_sum = counts, sum
				end
			end
		end
	end
	return best
end

--三作物：两个独立方程定出一条零空间射线，取叉积
local function Solve3(a, b, c)
	local r1 = { a[1], b[1], c[1] }
	local r2 = { a[2], b[2], c[2] }
	local x = {
		r1[2] * r2[3] - r1[3] * r2[2],
		r1[3] * r2[1] - r1[1] * r2[3],
		r1[1] * r2[2] - r1[2] * r2[1],
	}

	if x[1] == 0 and x[2] == 0 and x[3] == 0 then
		return Solve3Parallel(r1, r2)--叉积为零 = 秩只有 1，射线法失效
	end

	if x[1] < 0 and x[2] < 0 and x[3] < 0 then
		for i = 1, 3 do
			x[i] = -x[i]
		end
	end
	return x
end

--求一组作物的互补比；返回各作物数量(最简整数比)，无解返回 nil
local function Solve(crops)
	local n = #crops
	if n < 2 or n > MAX_CROPS then
		return nil
	end

	--第三分量 = -前两分量之和，故解前两个方程即等价于三个
	local vs = {}
	for i, plant in ipairs(crops) do
		local d = GetDelta(plant)
		if d == nil then
			return nil
		end
		vs[i] = { d[1], d[2] }
	end

	local counts
	if n == 2 then
		counts = Solve2(vs[1], vs[2])
	elseif n == 3 then
		counts = Solve3(vs[1], vs[2], vs[3])
	end

	if counts == nil then
		return nil
	end
	for _, v in ipairs(counts) do
		if v <= 0 then
			return nil--必须每种都种，出现 0 或负数说明这组不成立
		end
	end

	counts = Simplify(counts)
	if not IsBalanced(crops, counts) then
		return nil
	end
	return counts
end

------------ 比组枚举 ------------

--枚举所有"包含全部选中作物"的互补比组：selected 选中作物、pool 候选搭档(应已按季节筛过且不含 selected)、max_crops 组内作物数上限、max_plants 总株数上限(nil 不限制)；返回 { {crops, counts}, ... }，按总株数少→作物名字典序
function Nutrient.FindGroups(selected, pool, max_crops, max_plants)
	local out = {}
	local n_sel = #selected
	if n_sel == 0 then
		return out
	end

	local limit = math.min(max_crops or MAX_CROPS, MAX_CROPS)--上限不会超过求解器能力
	if limit < n_sel then
		limit = n_sel--选中的比上限还多时，至少要能把它们本身凑成一组
	end
	local max_extra = limit - n_sel

	local crops = { unpack(selected) }

	local function Try(extra)
		for i, plant in ipairs(extra) do
			crops[n_sel + i] = plant
		end

		local counts = Solve(crops)
		if counts ~= nil and (max_plants == nil or Sum(counts) <= max_plants) then
			--快照要在清空搭档之前取，否则只留下选中作物
			table.insert(out, { crops = { unpack(crops) }, counts = counts })
		end

		for i = 1, #extra do
			crops[n_sel + i] = nil
		end
	end

	--从 pool 里挑 extra_n 个搭档，组合枚举
	local extra = {}
	local function Combine(start, left)
		if left == 0 then
			Try(extra)
			return
		end
		for i = start, #pool do
			extra[#extra + 1] = pool[i]
			Combine(i + 1, left - 1)
			extra[#extra] = nil
		end
	end

	for extra_n = 0, max_extra do
		Combine(1, extra_n)
	end

	--总数少的排前面，同数按作物名字典序，保证结果稳定
	table.sort(out, function(a, b)
		local sa, sb = Sum(a.counts), Sum(b.counts)
		if sa ~= sb then
			return sa < sb
		end
		return table.concat(a.crops, ",") < table.concat(b.crops, ",")
	end)

	return out
end
