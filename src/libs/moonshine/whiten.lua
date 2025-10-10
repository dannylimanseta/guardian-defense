-- Simple whiten flash effect for Moonshine
-- Blends the texture towards white by `amount` (0..1)

return function(moonshine)
  local shader = love.graphics.newShader[[
    extern number amount; // 0..1
    vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _)
    {
      vec4 px = Texel(texture, tc) * color;
      vec3 outc = mix(px.rgb, vec3(1.0, 1.0, 1.0), clamp(amount, 0.0, 1.0));
      return vec4(outc, px.a);
    }
  ]]

  local setters = {}
  setters.amount = function(v) shader:send("amount", v or 0) end

  return moonshine.Effect{
    name = "whiten",
    shader = shader,
    setters = setters,
    defaults = { amount = 0 }
  }
end


