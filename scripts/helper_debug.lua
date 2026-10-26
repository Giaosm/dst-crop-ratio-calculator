--调试日志(开关关闭时第一行return，零开销)
function HelperDebug(...)
	if not HelperConfig.debug then return end
	print("[新种植计算器|调试] " .. string.format(...))
end
