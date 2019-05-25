//
//  ImageManager.swift
//  PhotoFlow
//
//  Created by Til Blechschmidt on 23.05.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import UIKit
import CoreData
import ReactiveSwift

enum ImageListEntry {
    case image(id: ImageEntity.ID)
    case group(withContents: [ImageListEntry])
}

enum ImageManagerError: Error {
    case imageNotFound
    case unableToReadImage
}

class ImageManager {
    private let document: ProjectDocument
    private let queueScheduler = QueueScheduler.init(qos: .utility, name: "ImageEntity rendering", targeting: nil)

    init(document: ProjectDocument) {
        self.document = document
    }

    func imageList() -> [ImageListEntry] {
        let entities = self.document.images

        guard let firstItem = entities.first else {
            return []
        }

        var previousHash: ImageHash = firstItem.imageHash
        var currentGroup: [ImageListEntry] = [.image(id: firstItem.objectID)]
        var results: [ImageListEntry] = []

        for entity in entities[1...] {
            if !entity.imageHash.isSimilar(to: previousHash) {
                results.append(
                    currentGroup.count > 1 ? .group(withContents: currentGroup) : currentGroup[0]
                )
                currentGroup = []
            }

            currentGroup.append(.image(id: entity.objectID))
            previousHash = entity.imageHash
        }

        return results
    }

    /// Attempts to fetch an image from the document. Only execute on the main thread!
    ///
    /// - Parameter id: Internal core data object id.
    /// - Returns: Fetched image. nil if id is invalid.
    func imageEntity(withID id: ImageEntity.ID) -> ImageEntity? {
        return document.managedObjectContext.object(with: id) as? ImageEntity
    }

    func fetchImageData(ofImageWithID id: ImageEntity.ID, thumbnail: Bool = false) -> SignalProducer<Data, Error> {
        let fetchContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        fetchContext.parent = document.managedObjectContext

        return SignalProducer { observer, _ in
            fetchContext.perform {
                guard let imageEntity = fetchContext.object(with: id) as? ImageEntity else {
                    observer.send(error: ImageManagerError.imageNotFound)
                    return
                }

                let optionalData = thumbnail ? imageEntity.thumbnailData : imageEntity.data
                guard let data = optionalData else {
                    observer.send(error: ImageManagerError.unableToReadImage)
                    return
                }

                observer.send(value: data)
                observer.sendCompleted()
            }
        }.observe(on: queueScheduler)
    }

    func fetchMetadata(ofImageWithID id: ImageEntity.ID) -> SignalProducer<ImageMetadata, Error> {
        return fetchImageData(ofImageWithID: id).attemptMap { data in
            guard let image = CIImage(data: data) else {
                throw ImageManagerError.unableToReadImage
            }

            return ImageMetadata(from: image)
        }
    }

    func fetchImage(withID id: ImageEntity.ID, thumbnail: Bool = false) -> SignalProducer<UIImage, Error> {
        return fetchImageData(ofImageWithID: id, thumbnail: true).attemptMap { data in
            guard let image = UIImage(data: data) else {
                throw ImageManagerError.unableToReadImage
            }

            return image
        }
    }
}
