import CoreTransferable
import UniformTypeIdentifiers
import Foundation

/// Import a file representation while its temporary URL is valid, with bounded reads.
struct PhotoSelectionFile: Transferable, Sendable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            PhotoSelectionFile(data: try await ImageFileLoader().load(received.file))
        }
    }
}
