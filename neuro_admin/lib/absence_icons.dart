import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

IconData absenceIcon(AvailabilityType type) => switch (type) {
  AvailabilityType.vacation => Icons.beach_access_outlined,
  AvailabilityType.sickLeave => Icons.healing_outlined,
  AvailabilityType.conference => Icons.groups_outlined,
  AvailabilityType.externalRoatation => Icons.flight_takeoff,
  AvailabilityType.duty24 => Icons.nights_stay_outlined,
  AvailabilityType.postDuty => Icons.hotel_outlined,
  AvailabilityType.zamLateShift => Icons.schedule_outlined,
  AvailabilityType.zamDaytime => Icons.wb_sunny_outlined,
  AvailabilityType.otherOutpatientClinic => Icons.medical_services_outlined,
  AvailabilityType.otherAbsence => Icons.event_busy_outlined,
  AvailabilityType.available => Icons.event_available_outlined,
  AvailabilityType.efDay => Icons.event_note_outlined,
};
