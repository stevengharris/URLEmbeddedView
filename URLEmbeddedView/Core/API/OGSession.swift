//
//  File.swift
//  URLEmbeddedView
//
//  Created by marty-suzuki on 2017/10/08.
//

import Foundation

public enum URLEmbeddedViewError: Error {
    case invalidURLString(String)
}

public enum Result<T> {
    case success(T)
    case failure(Error)
    
    var value: T? {
        if case .success(let value) = self { return value }
        return nil
    }
    
    var error: Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

@objc public final class Task: NSObject {
    private var task: URLSessionTask?
    private(set) var isExpired: Bool
    let uuidString: String
    
    override init() {
        self.task = nil
        self.isExpired = false
        self.uuidString = UUID().uuidString
        super.init()
    }
    
    fileprivate func setTask(_ task: URLSessionTask) {
        self.task = task
    }
    
    func expire(shouldContinueDownloading: Bool) {
        isExpired = true
        if !shouldContinueDownloading {
            task?.cancel()
        }
    }
}

protocol OGSessionType: class {
    func send<T: OGRequest>(_ request: T, task: Task, success: @escaping (T.Response, Bool) -> Void, failure: @escaping (OGSession.Error, Bool) -> Void) -> Task
}

final class OGSession: OGSessionType {
    enum Error: Swift.Error {
        case noData
        case castFaild
        case jsonDecodeFaild
        case htmlDecodeFaild
        case imageGenerateFaild
        case other(Swift.Error)
    }
    
    private let session: URLSession
    private var taskCollection: [String : Task] = [:]
    
    init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }
    
    @discardableResult
    func send<T: OGRequest>(_ request: T, task: Task = .init(), success: @escaping (T.Response, Bool) -> Void, failure: @escaping (OGSession.Error, Bool) -> Void) -> Task {
        let uuidString = task.uuidString
        let dataTask = session.dataTask(with: request.urlRequest) { [weak self] data, response, error in
            let isExpired = self?.taskCollection[uuidString]?.isExpired ?? true
            self?.taskCollection.removeValue(forKey: uuidString)
            if let error = error {
                failure((error as? Error) ?? .other(error), isExpired)
                return
            }
            guard let data = data else {
                failure(.noData, isExpired)
                return
            }
            do {
                let response = try T.response(data: data)
                success(response, isExpired)
            } catch let e as Error {
                failure(e, isExpired)
            } catch let e {
                failure(.other(e), isExpired)
            }
        }
        task.setTask(dataTask)
        taskCollection[task.uuidString] = task
        dataTask.resume()
        return task
    }
}
