# Remaining OperationConfigView.swift Updates Needed

## RreamOut and ReamIn Configs Need Keyboard Type Modifiers

The following TextFields in `reamOutConfig` and `reamInConfig` need the iOS keyboard modifiers added:

### For reamOutConfig:
```swift
// Add to all numeric TextFields:
#if os(iOS)
.keyboardType(.decimalPad)
.focused($focusedField, equals: .appropriateField)
#endif
```

**Fields needing updates:**
1. Start MD - `.focused($focusedField, equals: .startMD)`
2. End MD - `.focused($focusedField, equals: .endMD)`
3. Target ESD - `.focused($focusedField, equals: .targetESD)`
4. Step Size - `.focused($focusedField, equals: .step)`
5. Trip Speed - `.focused($focusedField, equals: .tripSpeed)`
6. Pump Rate - `.focused($focusedField, equals: .reamPumpRate)`
7. Control MD - `.focused($focusedField, equals: .controlMD)`
8. Float Crack - `.focused($focusedField, equals: .crackFloat)`
9. Eccentricity - `.focused($focusedField, equals: .eccentricity)`

### For reamInConfig:
**Fields needing updates:**
1. Start MD - `.focused($focusedField, equals: .startMD)`
2. End MD - `.focused($focusedField, equals: .endMD)`
3. Target ESD - `.focused($focusedField, equals: .targetESD)`
4. Pipe OD - `.focused($focusedField, equals: .pipeOD)`
5. Pipe ID - `.focused($focusedField, equals: .pipeID)`
6. Step Size - `.focused($focusedField, equals: .tripInStep)`
7. Trip Speed - `.focused($focusedField, equals: .tripInSpeed)`
8. Pump Rate - `.focused($focusedField, equals: .reamPumpRate)`
9. Control MD - `.focused($focusedField, equals: .controlMD)`

## Pattern to Apply

For each TextField in these configs, follow this pattern:

```swift
TextField("Label", value: $operation.field, format: .number)
    .textFieldStyle(.roundedBorder)
    .frame(width: 120)
    #if os(iOS)
    .keyboardType(.decimalPad)
    .focused($focusedField, equals: .fieldName)
    #endif
```

## Status
- ✅ tripOutConfig - COMPLETE
- ✅ tripInConfig - COMPLETE  
- ❌ reamOutConfig - NEEDS UPDATE
- ❌ reamInConfig - NEEDS UPDATE
- ✅ circulateConfig - COMPLETE
- ✅ PumpQueueEditor - COMPLETE

## Next Steps
Apply the same pattern used in tripOutConfig and tripInConfig to reamOutConfig and reamInConfig. This will complete the keyboard support for all operation types.
