import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: PluginCatalogService
    @EnvironmentObject private var runtime: PluginRuntime
    @EnvironmentObject private var streams: StremioStreamService
    @EnvironmentObject private var torrentEngine: TorrentEngine
    @State private var downloadsBytes: UInt64 = 0
    @State private var confirmingDelete = false

    private var nothingToDelete: Bool {
        torrentEngine.states.isEmpty && downloadsBytes == 0
    }

    private var downloadsSizeText: String {
        if nothingToDelete { return "Sin descargas" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: downloadsBytes), countStyle: .file)
    }

    private func refreshDownloadsSize() {
        downloadsBytes = torrentEngine.downloadsSize()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Acerca de") {
                    LabeledContent("App", value: "Kino iOS")
                    LabeledContent("Versión", value: "0.5.0 (Fase 4b)")
                    LabeledContent("Bundle ID", value: "com.sanchezho.KinoiOS")
                    LabeledContent("iOS mínimo", value: "18.0")
                    Text("Reescritura limpia para iOS de Kino TV. No es una conversión del APK de Android: la interfaz, la reproducción y el runtime de plugins están reescritos en Swift. Fase 2: catálogos reales de Internet Archive y Cinemeta, con pósters y reproducción.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("kinotvapp.github.io", destination: URL(string: "https://kinotvapp.github.io/en/")!)
                }
                Section("Runtime de plugins (JavaScriptCore)") {
                    LabeledContent("Estado", value: runtime.status)
                    if let name = runtime.pluginInfo["name"], !name.isEmpty {
                        LabeledContent("Plugin", value: name)
                    }
                    if let version = runtime.pluginInfo["version"], !version.isEmpty {
                        LabeledContent("Versión del plugin", value: version)
                    }
                    if let api = runtime.pluginInfo["apiVersion"], !api.isEmpty {
                        LabeledContent("apiVersion", value: api)
                    }
                    if !runtime.exportedFunctions.isEmpty {
                        Text("Funciones exportadas detectadas: \(runtime.exportedFunctions.joined(separator: ", "))")
                            .font(.caption)
                    }
                    if !runtime.diagnostics.isEmpty {
                        ForEach(runtime.diagnostics, id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Plugins del catálogo (\(catalog.plugins.count))") {
                    if let error = catalog.loadError {
                        Text(error).foregroundStyle(.orange)
                    }
                    ForEach(catalog.plugins) { plugin in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.displayName).bold()
                            Text(plugin.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if plugin.needsSetup == true {
                                Text("Necesita configuración")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Section("Add-on de streams (Stremio)") {
                    TextField("https://torrentio.strem.fun", text: $streams.baseURL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    Button("Restablecer") {
                        streams.resetToDefault()
                    }
                    Text("El detalle de cada título lista las fuentes de este add-on. Los streams con URL directa y los torrents se reproducen con VLC (motor integrado), que abre MP4, MKV y más formatos; los torrents se sirven por el servidor local.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Descargas (torrents)") {
                    LabeledContent("Espacio usado", value: downloadsSizeText)
                    Button("Eliminar descargas", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(nothingToDelete)
                    .confirmationDialog(
                        "¿Eliminar todas las descargas?",
                        isPresented: $confirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Eliminar descargas", role: .destructive) {
                            torrentEngine.removeAllDownloads()
                            refreshDownloadsSize()
                        }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("Se detendrán los torrents y se borrarán sus archivos del dispositivo.")
                    }
                    Toggle("Compartir al terminar (seeding)", isOn: Binding(
                        get: { torrentEngine.seedAfterFinish },
                        set: { torrentEngine.seedAfterFinish = $0 }
                    ))
                    Text("Desactivado: el torrent se pausa al terminar la descarga. Activado: sigue compartiendo (subiendo datos) después de terminar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Procedencia") {
                    Text("El catálogo y el plugin incluidos vienen del APK de Kino TV 0.9.83 (Apache-2.0). Detalle en KinoiOS/Resources/README-PROVENANCE.md. En Fase 2 la app descarga catálogos de archive.org y Cinemeta y reproduce video de archive.org; no aloja contenido.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
            .onAppear { refreshDownloadsSize() }
        }
    }
}
