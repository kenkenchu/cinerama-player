import Foundation

// Mac routing stays outside the shared Home view model.
extension HomeViewModel {
    func showAllRoute(for shelf: HomePersonalizedShelf) -> AppNavigationRoute? {
        guard let library = shelf.showAllLibrary else { return nil }
        return .libraryGenre(library: library, genre: shelf.genre)
    }
}
