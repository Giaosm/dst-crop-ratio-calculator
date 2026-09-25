name = "简易种植计算器"
description = [[只支持3种作物的配比计算]]
author = "哇唧唧哇"

version = "0.0.1.0"--整体.大章节.小章节.优化、修Bug

api_version = 10

dont_starve_compatible = false--仅DST联机版，不支持单机原版
reign_of_giants_compatible = false--仅DST联机版，不支持单机巨人国
dst_compatible = true
all_clients_require_mod = false--纯客户端模组，服务端无需安装
client_only_mod = true--纯客户端模组
icon = "modicon.tex"
icon_atlas = "modicon.xml"

local function Subtitle(name)
	return {
		name = name,
		label = name,
		options = { {description = "", data = false}, },
		default = false,
	}
end

configuration_options =
{
	Subtitle("基础"),
	{
		name = "calc_ui_key",
		label = "计算器快捷键",
		hover = "游戏内按此键开关计算器UI。",
		options =
		{
			{description = "R", data = 114, hover = "按R键开关UI"},	--KEY_R
			{description = "O", data = 111, hover = "按O键开关UI"},	--KEY_O
			{description = "G", data = 103, hover = "按G键开关UI"},	--KEY_G
			{description = "H", data = 104, hover = "按H键开关UI"},	--KEY_H
			{description = "J", data = 106, hover = "按J键开关UI"},	--KEY_J
			{description = "K", data = 107, hover = "按K键开关UI"},	--KEY_K
			{description = "L", data = 108, hover = "按L键开关UI"},	--KEY_L
			{description = "X", data = 120, hover = "按X键开关UI"},	--KEY_X
			{description = "N", data = 110, hover = "按N键开关UI"},	--KEY_N
			{description = "F1", data = 282, hover = "按F1键开关UI"},	--KEY_F1
			{description = "F2", data = 283, hover = "按F2键开关UI"},	--KEY_F2
			{description = "F3", data = 284, hover = "按F3键开关UI"},	--KEY_F3
			{description = "F4", data = 285, hover = "按F4键开关UI"},	--KEY_F4
			{description = "F5", data = 286, hover = "按F5键开关UI"},	--KEY_F5
			{description = "F6", data = 287, hover = "按F6键开关UI"},	--KEY_F6
			{description = "F7", data = 288, hover = "按F7键开关UI"},	--KEY_F7
			{description = "F8", data = 289, hover = "按F8键开关UI"},	--KEY_F8
			{description = "F9", data = 290, hover = "按F9键开关UI"},	--KEY_F9
			{description = "F10", data = 291, hover = "按F10键开关UI"},	--KEY_F10
			{description = "F11", data = 292, hover = "按F11键开关UI"},	--KEY_F11
			{description = "F12", data = 293, hover = "按F12键开关UI"},	--KEY_F12
		},
		default = 107,
	},
	Subtitle("调试"),
	{
		name = "show_view_border",
		label = "视窗边框",
		hover = "在两个滚动视窗上显示边框线，便于调整布局",
		options =
		{
			{description = "关闭", data = false},
			{description = "开启", data = true},
		},
		default = false,
	},
	{
		name = "debug_switch",
		label = "调试模式",
		options =
		{
			{description = "关闭", data = false},
			{description = "开启", data = true},
		},
		default = false,
	},
}
