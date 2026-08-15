Locales = Locales or { en = {}, tr = {} }
Locales.en = {
    startup = {
        ready = 'gnsh-telecom started',
        stopped = 'gnsh-telecom stopped',
        invalidConfig = 'gnsh-telecom refused to start because configuration is invalid',
    },
}

Locale = Locale or {}

function Locale.Translate(locale, key)
    local selected = Locales[locale] or Locales[Config.Locale] or Locales.en
    local value = selected
    for segment in tostring(key):gmatch('[^.]+') do
        if type(value) ~= 'table' then return tostring(key) end
        value = value[segment]
    end
    return type(value) == 'string' and value or tostring(key)
end
