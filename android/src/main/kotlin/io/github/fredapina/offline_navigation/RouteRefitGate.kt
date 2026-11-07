package io.github.fredapina.offline_navigation

/**
 * Decides when the route preview has to be fitted to the screen again.
 *
 * When a route has been built, the engine zooms the map to it, but only if the
 * map's drawing engine exists at that moment; otherwise the zoom is silently
 * dropped and the preview stays at the zoom it started with. A short route is
 * built in well under a second, often before the map of a freshly opened page
 * has a drawing engine, so its preview came up zoomed far out: blank without
 * the base world map, a tiny world with it.
 *
 * So: when a route is built while the map is not ready, remember that, and when
 * the map becomes ready ask the engine for the route once more, which makes it
 * fit the route this time.
 */
internal class RouteRefitGate {
  private var mapReady = false
  private var refitPending = false

  /** A route has just been built. */
  fun onRouteBuilt() {
    refitPending = !mapReady
  }

  /**
   * The map's drawing engine is available. Safe to call more than once.
   * Returns true when the route must be fitted now.
   */
  fun onMapReady(): Boolean {
    mapReady = true
    val refit = refitPending
    refitPending = false
    return refit
  }

  /** The map view is gone, so the next route is built without a drawing engine. */
  fun onMapLost() {
    mapReady = false
  }

  /** The route was closed: there is nothing left to fit. */
  fun onRouteClosed() {
    refitPending = false
  }
}
