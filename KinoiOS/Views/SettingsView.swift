import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: PluginCatalogService
    @EnvironmentObject private var runtime: PluginRuntime

    var body: some View {
        NavigationStack {
            List {
                Section("Acerca de") {
                    LabeledContent("App", value: "Kino iOS")
                    LabeledContent("Versión", value: "0.1.0 (Fase 1)")
                    LabeledContent("Bundle ID", value: "com.sanchezho.KinoiOS")
                    LabeledContent("iOS mínimo", value: "17.0")
                    Text("Reescritura limpia para iOS de Kino TV. No es una conversión del APK de Android: la interfaz, la reproducción y el runtime de plugins están reescritos en Swift.")
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
                Section("Procedencia") {
                    Text("El catálogo y el plugin incluidos vienen del APK de Kino TV 0.9.83 (Apache-2.0). Detalle en KinoiOS/Resources/README-PROVENANCE.md. Esta app no aloja contenido ni reproduce fuentes de terceros en Fase 1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
