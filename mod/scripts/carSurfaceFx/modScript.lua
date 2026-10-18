-- Car Surface FX: load the extension and keep it across level loads. The old modder API (surfaceFX, MODDER_API.md) loads first so other mods can register their pages at once.
extensions.load('surfaceFXStore')
extensions.load('surfaceFX')
extensions.load('surfaceFXBody')
extensions.load('carSurfaceFx')
setExtensionUnloadMode('carSurfaceFx', 'manual')
setExtensionUnloadMode('surfaceFX', 'manual')
