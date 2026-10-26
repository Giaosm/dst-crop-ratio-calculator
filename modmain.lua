--参考坐着轮椅玩勋章2：设置mod环境可访问全局(TUNING等)
GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})

--本模组的配置项，只放在自己的环境里，不写进游戏全局 TUNING(避免和其它模组撞名互相覆盖)
HelperConfig =
{
	debug = GetModConfigData("debug_switch"),--调试开关
	key = GetModConfigData("calc_ui_key"),--计算器开关快捷键，顶层读取供客户端UI使用
	view_border = GetModConfigData("show_view_border"),--视窗边框开关
}

--加载顺序：调试日志 → 养分算法 → UI，按依赖顺序
modimport("scripts/helper_debug.lua")--调试日志
modimport("scripts/helper_plant_nutrient.lua")--养分算法
modimport("scripts/helper_plant_calc_ui.lua")--种植计算器UI(客户端)
