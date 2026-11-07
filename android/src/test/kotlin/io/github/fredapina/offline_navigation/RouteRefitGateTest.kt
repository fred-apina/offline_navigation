package io.github.fredapina.offline_navigation

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class RouteRefitGateTest {
  @Test
  fun routeBuiltBeforeTheMapIsReady_isFittedWhenTheMapBecomesReady() {
    val gate = RouteRefitGate()
    gate.onRouteBuilt()
    assertTrue(gate.onMapReady())
  }

  @Test
  fun routeBuiltAfterTheMapIsReady_needsNoRefit() {
    val gate = RouteRefitGate()
    gate.onMapReady()
    gate.onRouteBuilt()
    assertFalse(gate.onMapReady())
  }

  @Test
  fun theRefitHappensOnlyOnce() {
    val gate = RouteRefitGate()
    gate.onRouteBuilt()
    assertTrue(gate.onMapReady())
    // The map reports "ready" more than once (created, restored, initialised).
    assertFalse(gate.onMapReady())
    assertFalse(gate.onMapReady())
  }

  @Test
  fun aRouteBuiltBeforeTheMapWasLost_isStillFittedWhenAMapAppears() {
    val gate = RouteRefitGate()
    gate.onRouteBuilt()
    gate.onMapLost()
    assertTrue(gate.onMapReady())
  }

  @Test
  fun aClosedRoute_isNeverFitted() {
    val gate = RouteRefitGate()
    gate.onRouteBuilt()
    gate.onRouteClosed()
    assertFalse(gate.onMapReady())
  }

  @Test
  fun aNewMapViewForTheNextRoute_startsNotReady() {
    val gate = RouteRefitGate()
    gate.onMapReady()
    gate.onMapLost() // the first page closed
    gate.onRouteBuilt() // the next page builds before its map exists
    assertTrue(gate.onMapReady())
  }

  @Test
  fun aMapThatBecomesReadyWithNoRoute_asksForNothing() {
    val gate = RouteRefitGate()
    assertFalse(gate.onMapReady())
  }
}
