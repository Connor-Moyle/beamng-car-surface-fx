-- Car Surface FX: extension hooks that run every frame (onPreRender, onUpdate) get a safety net. One error switches that module's hooks off and is logged once, instead of repeating
-- every frame for every player; module.resume() tries again, module.failure() says what went wrong. The same pattern as the main extension's update.
local G = {}

function G.wrap(M, tag, names)
  local failed
  for _, name in ipairs(names) do
    local f = M[name]
    if f then
      M[name] = function(...)
        if failed then return end
        local ok, err = pcall(f, ...)
        if not ok then
          failed = tostring(err)
          log('E', tag, 'switched off after an error in ' .. name .. ': ' .. failed .. ' (resume() to try again)')
        end
      end
    end
  end
  function M.resume() failed = nil return 'resumed' end
  function M.failure() return failed end
  return M
end

return G
