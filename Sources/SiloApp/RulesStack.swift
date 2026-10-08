// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SiloStore
import SmdKit
import SmdSidecar
import Wire

/// The rules that apply to a binding now, as layers above its ruleset: the binding's own, then each
/// container's of its lineage, read from where the library — or, before a binding's first
/// placement, the silo — keeps them. One place, so that an application and the background check
/// resolve through the same stack. `LayeredRulesets.md`, *The stack*.
@Singleton
package struct RulesStack: Sendable {
    private let config: SiloConfig
    private let index: Index
    private let staged: BindingRulesStore

    @Inject
    package init(config: SiloConfig, index: Index, staged: BindingRulesStore) {
        self.config = config
        self.index = index
        self.staged = staged
    }

    /// A binding's lineage, root first, from the repository documents it carries.
    package func lineage(of binding: Binding) throws -> [SmdKit.Container] {
        try binding.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
    }

    /// The layers above the ruleset, nearest first: the binding's own rules, when it has any, then
    /// the rules in force of each container of the lineage, from the item's own up, as the index
    /// holds their sidecars now. A container with no sidecar, or no `<rules>`, has no layer; rules
    /// that cannot be read refuse the application.
    package func layers(of binding: Binding, lineage: [SmdKit.Container]) throws -> [RulesLayer] {
        guard let library = config.library(binding.library) else { return [] }
        var layers: [RulesLayer] = []
        do throws(RulesLayerError) {
            if let own = try bindingLayer(of: binding, lineage: lineage) { layers.append(own) }
        } catch {
            throw Unresolvable(reason: error.description)
        }
        for container in lineage.reversed() {
            guard let row = try index.container(container.id), let reference = try index.sidecar(container.id)?.rules else { continue }
            let folder = row.folder.isEmpty ? library.root : library.root.appendingPathComponent(row.folder, isDirectory: true)
            do throws(RulesLayerError) {
                layers.append(try RulesLayerFile.read(.container(container.id.value), reference, in: folder))
            } catch {
                throw Unresolvable(reason: error.description)
            }
        }
        return layers
    }

    /// What the library holds of a binding's rules: the folder of the container holding its item,
    /// whether a presentation made from the binding has been placed there, and the item's
    /// reference to the binding's rules in force, when it names one.
    package struct Home {
        package var library: LibraryConfig
        package var folder: URL
        package var sidecar: URL
        package var placed: Bool
        package var reference: SidecarRules?
    }

    package func home(of binding: Binding, lineage: [SmdKit.Container]) throws -> Home? {
        guard let library = config.library(binding.library), let container = lineage.last,
              let row = try index.container(container.id), let sidecar = try index.sidecar(container.id)
        else { return nil }
        let folder = row.folder.isEmpty ? library.root : library.root.appendingPathComponent(row.folder, isDirectory: true)
        return Home(
            library: library, folder: folder, sidecar: folder.appendingPathComponent(SidecarFile.fileName),
            placed: sidecar.presentations[binding.item]?.contains { $0.source?.binding == binding.id } ?? false,
            reference: sidecar.bindingRules[binding.item]?.first { $0.binding == binding.id }?.rules
        )
    }

    /// The binding's rules in force: in the library once a presentation made from it is placed, and
    /// in the silo's staging until then.
    func bindingLayer(of binding: Binding, lineage: [SmdKit.Container]) throws(RulesLayerError) -> RulesLayer? {
        let home = try? self.home(of: binding, lineage: lineage)
        if let home, home.placed {
            return try home.reference.map { reference throws(RulesLayerError) in try RulesLayerFile.read(.binding(binding.id), reference, in: home.folder) }
        }
        guard let version = staged.versions(of: binding.id).last else { return nil }
        return try RulesLayerFile.read(.binding(binding.id), version: version, file: staged.file(of: binding.id, version: version))
    }
}
