import 'package:flutter/material.dart';

import 'models.dart';

/// Maps an engine turn direction to a Material icon for the instruction banner.
IconData turnIcon(CarTurn turn) => switch (turn) {
      CarTurn.noTurn || CarTurn.goStraight || CarTurn.startAtEndOfStreet => Icons.straight,
      CarTurn.turnRight => Icons.turn_right,
      CarTurn.turnSharpRight => Icons.turn_sharp_right,
      CarTurn.turnSlightRight => Icons.turn_slight_right,
      CarTurn.turnLeft => Icons.turn_left,
      CarTurn.turnSharpLeft => Icons.turn_sharp_left,
      CarTurn.turnSlightLeft => Icons.turn_slight_left,
      CarTurn.uTurnLeft || CarTurn.uTurnRight => Icons.u_turn_left,
      CarTurn.enterRoundAbout ||
      CarTurn.leaveRoundAbout ||
      CarTurn.stayOnRoundAbout =>
        Icons.roundabout_left,
      CarTurn.exitHighwayToLeft => Icons.ramp_left,
      CarTurn.exitHighwayToRight => Icons.ramp_right,
      CarTurn.reachedYourDestination => Icons.flag,
    };
