/// Official-position pitch slots for every supported formation.
///
/// This table is the FRONTEND MIRROR of ``FORMATION_SLOTS`` in
/// ``backend/ml/xi_predictor.py``. The backend is the single source of truth
/// for the slot LABELS and their ORDER (the order is the ``slot_index`` the
/// API returns for each player): index 0 is the goalkeeper, then the lines run
/// back to front, and within each line the slots run in a fixed order. This
/// file adds only the pitch geometry (x, y in 0..1, with x increasing to the
/// right and y increasing toward the team's own goal) and the coarse group for
/// colouring. Keep the labels, order, and coarse groups in sync with the
/// backend; the ``slot_index`` returned by the API indexes directly into these
/// lists.
library;

class FormationSlot {
  const FormationSlot(this.label, this.coarse, this.x, this.y);

  /// Official position label, e.g. RB, RCB, DM, RW, ST.
  final String label;

  /// Coarse group (GK, DEF, MID, FWD) used for the role colour.
  final String coarse;

  /// Normalised pitch coordinates in 0..1.
  final double x;
  final double y;
}

const double _yGk = 0.90;
const double _yDef = 0.74;
const double _yFwd = 0.17;

const Map<String, List<FormationSlot>> kFormationSlots = {
  '4-4-2': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('RM', 'MID', 0.86, 0.45),
    FormationSlot('RCM', 'MID', 0.62, 0.45),
    FormationSlot('LCM', 'MID', 0.38, 0.45),
    FormationSlot('LM', 'MID', 0.14, 0.45),
    FormationSlot('RST', 'FWD', 0.62, _yFwd),
    FormationSlot('LST', 'FWD', 0.38, _yFwd),
  ],
  '4-3-3': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('DM', 'MID', 0.50, 0.56),
    FormationSlot('RCM', 'MID', 0.70, 0.42),
    FormationSlot('LCM', 'MID', 0.30, 0.42),
    FormationSlot('RW', 'FWD', 0.84, _yFwd),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
    FormationSlot('LW', 'FWD', 0.16, _yFwd),
  ],
  '4-2-3-1': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('RDM', 'MID', 0.64, 0.56),
    FormationSlot('LDM', 'MID', 0.36, 0.56),
    FormationSlot('RAM', 'MID', 0.80, 0.36),
    FormationSlot('CAM', 'MID', 0.50, 0.36),
    FormationSlot('LAM', 'MID', 0.20, 0.36),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
  ],
  '4-5-1': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('RM', 'MID', 0.88, 0.44),
    FormationSlot('RCM', 'MID', 0.69, 0.44),
    FormationSlot('CM', 'MID', 0.50, 0.44),
    FormationSlot('LCM', 'MID', 0.31, 0.44),
    FormationSlot('LM', 'MID', 0.12, 0.44),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
  ],
  '4-1-4-1': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('DM', 'MID', 0.50, 0.57),
    FormationSlot('RM', 'MID', 0.86, 0.40),
    FormationSlot('RCM', 'MID', 0.62, 0.40),
    FormationSlot('LCM', 'MID', 0.38, 0.40),
    FormationSlot('LM', 'MID', 0.14, 0.40),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
  ],
  '4-3-2-1': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('RCM', 'MID', 0.70, 0.52),
    FormationSlot('CDM', 'MID', 0.50, 0.52),
    FormationSlot('LCM', 'MID', 0.30, 0.52),
    FormationSlot('RAM', 'MID', 0.64, 0.33),
    FormationSlot('LAM', 'MID', 0.36, 0.33),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
  ],
  '4-2-2-2': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RB', 'DEF', 0.86, _yDef),
    FormationSlot('RCB', 'DEF', 0.62, _yDef),
    FormationSlot('LCB', 'DEF', 0.38, _yDef),
    FormationSlot('LB', 'DEF', 0.14, _yDef),
    FormationSlot('RDM', 'MID', 0.64, 0.54),
    FormationSlot('LDM', 'MID', 0.36, 0.54),
    FormationSlot('RAM', 'MID', 0.66, 0.35),
    FormationSlot('LAM', 'MID', 0.34, 0.35),
    FormationSlot('RST', 'FWD', 0.62, _yFwd),
    FormationSlot('LST', 'FWD', 0.38, _yFwd),
  ],
  '3-1-4-2': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RCB', 'DEF', 0.70, _yDef),
    FormationSlot('CB', 'DEF', 0.50, _yDef),
    FormationSlot('LCB', 'DEF', 0.30, _yDef),
    FormationSlot('DM', 'MID', 0.50, 0.58),
    FormationSlot('RM', 'MID', 0.86, 0.40),
    FormationSlot('RCM', 'MID', 0.62, 0.40),
    FormationSlot('LCM', 'MID', 0.38, 0.40),
    FormationSlot('LM', 'MID', 0.14, 0.40),
    FormationSlot('RST', 'FWD', 0.62, _yFwd),
    FormationSlot('LST', 'FWD', 0.38, _yFwd),
  ],
  '3-5-2': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RCB', 'DEF', 0.70, _yDef),
    FormationSlot('CB', 'DEF', 0.50, _yDef),
    FormationSlot('LCB', 'DEF', 0.30, _yDef),
    FormationSlot('RWB', 'MID', 0.90, 0.46),
    FormationSlot('RCM', 'MID', 0.69, 0.42),
    FormationSlot('CM', 'MID', 0.50, 0.42),
    FormationSlot('LCM', 'MID', 0.31, 0.42),
    FormationSlot('LWB', 'MID', 0.10, 0.46),
    FormationSlot('RST', 'FWD', 0.62, _yFwd),
    FormationSlot('LST', 'FWD', 0.38, _yFwd),
  ],
  '3-4-3': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RCB', 'DEF', 0.70, _yDef),
    FormationSlot('CB', 'DEF', 0.50, _yDef),
    FormationSlot('LCB', 'DEF', 0.30, _yDef),
    FormationSlot('RM', 'MID', 0.86, 0.44),
    FormationSlot('RCM', 'MID', 0.62, 0.44),
    FormationSlot('LCM', 'MID', 0.38, 0.44),
    FormationSlot('LM', 'MID', 0.14, 0.44),
    FormationSlot('RW', 'FWD', 0.84, _yFwd),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
    FormationSlot('LW', 'FWD', 0.16, _yFwd),
  ],
  '3-6-1': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RCB', 'DEF', 0.70, _yDef),
    FormationSlot('CB', 'DEF', 0.50, _yDef),
    FormationSlot('LCB', 'DEF', 0.30, _yDef),
    FormationSlot('RWB', 'MID', 0.92, 0.46),
    FormationSlot('RCM', 'MID', 0.71, 0.42),
    FormationSlot('RDM', 'MID', 0.57, 0.50),
    FormationSlot('LDM', 'MID', 0.43, 0.50),
    FormationSlot('LCM', 'MID', 0.29, 0.42),
    FormationSlot('LWB', 'MID', 0.08, 0.46),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
  ],
  '5-3-2': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RWB', 'DEF', 0.90, _yDef),
    FormationSlot('RCB', 'DEF', 0.69, _yDef),
    FormationSlot('CB', 'DEF', 0.50, _yDef),
    FormationSlot('LCB', 'DEF', 0.31, _yDef),
    FormationSlot('LWB', 'DEF', 0.10, _yDef),
    FormationSlot('RCM', 'MID', 0.70, 0.44),
    FormationSlot('CM', 'MID', 0.50, 0.44),
    FormationSlot('LCM', 'MID', 0.30, 0.44),
    FormationSlot('RST', 'FWD', 0.62, _yFwd),
    FormationSlot('LST', 'FWD', 0.38, _yFwd),
  ],
  '5-4-1': [
    FormationSlot('GK', 'GK', 0.50, _yGk),
    FormationSlot('RWB', 'DEF', 0.90, _yDef),
    FormationSlot('RCB', 'DEF', 0.69, _yDef),
    FormationSlot('CB', 'DEF', 0.50, _yDef),
    FormationSlot('LCB', 'DEF', 0.31, _yDef),
    FormationSlot('LWB', 'DEF', 0.10, _yDef),
    FormationSlot('RM', 'MID', 0.86, 0.44),
    FormationSlot('RCM', 'MID', 0.62, 0.44),
    FormationSlot('LCM', 'MID', 0.38, 0.44),
    FormationSlot('LM', 'MID', 0.14, 0.44),
    FormationSlot('ST', 'FWD', 0.50, _yFwd),
  ],
};

/// Coarse group (GK/DEF/MID/FWD) for a fine-position group, mirroring the
/// backend ``FINE_GROUP_TO_COARSE`` map. Used to colour a chip when only the
/// player's fine group is known (for example on the player detail card).
String coarseForFineGroup(String fine) {
  switch (fine.toUpperCase()) {
    case 'GK':
      return 'GK';
    case 'CB':
    case 'FB':
    case 'WB':
      return 'DEF';
    case 'DM':
    case 'CM':
    case 'AM':
      return 'MID';
    case 'W':
    case 'WF':
    case 'ST':
      return 'FWD';
    default:
      return '';
  }
}
