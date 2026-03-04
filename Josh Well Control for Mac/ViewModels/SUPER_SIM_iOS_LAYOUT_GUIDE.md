# Quick Reference: Super Simulation iOS Layout Guide

## 📱 iPhone Layout (Tabs)
Perfect for focused, single-task interaction:

```
┌─────────────────────────┐
│ Tab 1: OPERATIONS       │  ← Timeline list, swipe actions
├─────────────────────────┤
│ Tab 2: DETAIL           │  ← Config forms & results
├─────────────────────────┤
│ Tab 3: WELLBORE         │  ← Visual fluid column
├─────────────────────────┤
│ Tab 4: CHART (NEW!)     │  ← Interactive charts
└─────────────────────────┘
```

**Key Features**:
- Swipe right on operation → "Run From Here"
- Swipe left on operation → "Delete"
- Charts: Tap/drag to select data points
- 300px chart height optimized for phone

---

## 📱 iPad Portrait (Stacked)
Segmented picker at top for quick switching:

```
┌─────────────────────────────────┐
│ [Ops] [Detail] [Wellbore] [Chart] │ ← Segmented picker
├─────────────────────────────────┤
│                                 │
│        Selected View            │
│        (Full Height)            │
│                                 │
└─────────────────────────────────┘
```

---

## 💻 iPad Landscape (Split View) ⭐ BEST LAYOUT
Three-panel design for maximum efficiency:

```
┌─────────┬───────────────────────────┬──────────┐
│ OPS     │  [Detail] | [Chart] ←Tab  │ WELLBORE │
│ LIST    ├───────────────────────────┤          │
│         │                           │          │
│ • Trip  │   📊 CHART VIEW           │   🛢️     │
│   Out   │   or                      │          │
│         │   ⚙️ DETAIL VIEW          │          │
│ • Trip  │   (Collapsible Sections)  │          │
│   In    │                           │          │
│         │   ▼ Configuration         │          │
│ • Circ  │   ▶ Results (Expanded!)   │          │
│         │   ▶ Output State          │          │
│ [+ Add] │                           │  Slider  │
└─────────┴───────────────────────────┴──────────┘
  320px            Flexible               280px
```

**Workflow**:
1. Select operation from left sidebar
2. Toggle between Detail/Chart in center
3. Watch wellbore update in real-time on right
4. Collapse config section → see more result rows!

---

## 🎯 Collapsible Sections (iPad Landscape Only)

### Why?
Configuration forms are tall but rarely need constant visibility. Results tables are what you analyze!

### Sections:
- **▼ Configuration** (expanded by default)
  - All input parameters
  - Mud selectors
  - Advanced options

- **▼ Results** (expanded by default) ⭐ PRIMARY VIEW
  - Step-by-step tables
  - Scrubber slider
  - Export buttons

- **▶ Output State** (collapsed by default)
  - Final MD/TVD
  - ESD/SABP summary
  - Quick reference only

### Usage:
```
Tap disclosure arrow → Section collapses/expands
Animation is smooth and instant
More table rows visible when config collapsed!
```

---

## 📊 Chart Features (All Devices)

### Chart Types:
1. **ESD** - Mud column vs. Mud+BP
2. **Back Pressure** - Static vs. Dynamic SABP
3. **Pump Rate** - Flow rate with APL overlay

### Interaction:
- **Tap/Drag** anywhere on chart → Select point
- **Info Panel** appears showing details
- **Auto-dismiss** after 2 seconds (or tap X)
- **Legend Button** (ℹ️) → Show/hide legend
- **Zoom Slider** (iPad only) → 1x to 5x

### Smart Features:
- Background bands show operation type
- Vertical line follows global scrubber
- Charts scroll to keep scrubber visible
- Color-coded lines match operation colors

---

## 🔧 Bug Fix: Preset Mud ID Issue

### Problem (Before):
```
1. Save preset with "Custom Mud A" (UUID: abc-123)
2. Load preset in different project (no "Custom Mud A")
3. Operation keeps invalid UUID → CRASH or errors
```

### Solution (After):
```
1. Save preset with mud name + density + UUID
2. Load preset:
   a. Try UUID match first
   b. Fall back to name match
   c. Fall back to density match (±1 kg/m³)
   d. If no match → set to nil (user selects manually)
3. No crashes! Invalid UUIDs are cleared automatically.
```

---

## 💡 Pro Tips

### For iPhone Users:
- Use tabs to focus on one thing at a time
- Chart tab is great for field reviews
- Wellbore tab shows fluid changes clearly

### For iPad Users:
- **Landscape mode is king** for data analysis
- Collapse config section when reviewing results
- Use chart tab for presentations/reports
- Keep wellbore visible for spatial context

### For Charts:
- Drag continuously to "scrub" through timeline
- Legend shows what each color/line means
- Background bands help identify operation boundaries
- Zoom in on iPad for fine detail analysis

### For Presets:
- Presets now safely handle missing muds
- Double-check mud assignments after loading
- Save presets frequently during complex setups

---

## 🎨 Visual Design Language

### Colors:
- **Blue** - Trip Out operations
- **Green** - Trip In operations
- **Orange** - Circulation operations
- **Purple** - Ream Out operations
- **Pink** - Ream In operations
- **Cyan** - Mud + Back Pressure
- **Red** - Static SABP
- **Orange** - Dynamic SABP

### Status Badges:
- **Gray** - Pending
- **Blue** - Running
- **Green** - Complete
- **Red** - Error

### Symbols:
- 📊 Chart/Analysis
- ⚙️ Configuration
- 🛢️ Wellbore
- 📋 Results
- ℹ️ Legend/Info

---

## 🚀 What's New Summary

✅ **Full iOS Charts** - Touch-interactive, scrollable, zoomable  
✅ **Collapsible Sections** - More space for data tables  
✅ **Preset Bug Fixed** - No more invalid mud ID crashes  
✅ **Smart Layouts** - Optimized for each device size  
✅ **Feature Parity** - macOS, iPad, iPhone all equal  

**Result**: Professional drilling simulation analysis on any device, anywhere! 🎉
