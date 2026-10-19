-- Car Surface FX: load the extension and keep it across level loads. The old modder API (surfaceFX, MODDER_API.md) loads first so other mods can register their pages at once.
setExtensionUnloadMode('surfaceFXStore', 'manual')
extensions.load('surfaceFXStore')
setExtensionUnloadMode('surfaceFX', 'manual')
extensions.load('surfaceFX')
setExtensionUnloadMode('surfaceFXBody', 'manual')
extensions.load('surfaceFXBody')
setExtensionUnloadMode('carSurfaceFx', 'manual')
extensions.load('carSurfaceFx')
