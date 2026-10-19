-- Car Surface FX: load the extension and keep it across level loads. The old modder API (surfaceFX, MODDER_API.md) loads first so other mods can register their pages at once.
setExtensionUnloadMode('carSurfaceFx', 'manual')           -- (set before the load: 0.40 warns otherwise)
setExtensionUnloadMode('surfaceFX', 'manual')
extensions.load('surfaceFXStore')
extensions.load('surfaceFX')
extensions.load('surfaceFXBody')
extensions.load('carSurfaceFx')
