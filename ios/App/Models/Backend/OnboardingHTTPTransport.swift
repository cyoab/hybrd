import Foundation

/// An ephemeral session with no cookies/cache and no bearer-token redirects.
final class OnboardingHTTPTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  @MainActor static let shared = OnboardingHTTPTransport()
  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
    config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()
  @MainActor func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw BackendContractError.invalidResponse }
    return (data, http)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
