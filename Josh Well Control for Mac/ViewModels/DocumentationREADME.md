# Documentation Organization

This directory contains technical documentation and implementation guides for the Josh Well Control application.

## Structure

```
Documentation/
├── Technical/
│   ├── NumericalTripModel_SPE_Technical_Paper.md    # Comprehensive trip modeling paper
│   ├── CEMENTING_HYDRAULICS_ALIGNMENT.md            # Analysis of cement sim hydraulics
│   └── CEMENTING_HYDRAULICS_IMPLEMENTATION.md       # Implementation of unified hydraulics
│
├── Implementation/
│   ├── LOADING_SCREEN_IMPLEMENTATION.md             # Loading overlay for simulations
│   ├── LAUNCH_SCREEN_DOCUMENTATION.md               # App launch screen guide
│   ├── LAUNCH_SCREEN_VISUAL_GUIDE.md                # Visual design specs
│   └── BUILD_FIXES.md                               # Build error resolutions
│
└── README.md                                        # This file
```

## Purpose

### Technical Documentation
Papers and technical specifications for wellbore hydraulics simulations, modeling approaches, and algorithms.

### Implementation Guides
Step-by-step guides for features, UI components, and architectural changes.

## For AI Assistants

When working with this codebase:

1. **Always check** `/Documentation/` for relevant context before making changes
2. **Create new documentation** in the appropriate subfolder for significant features
3. **Update existing docs** when making changes to documented features
4. **Reference documentation** in code comments using relative paths

## Guidelines

### Creating New Documentation

**Technical Papers:**
- Place in `Technical/`
- Use descriptive names: `[Feature]_[Type]_[Version].md`
- Include equations, diagrams (ASCII), and references
- Follow academic paper structure (Abstract, Introduction, Methods, etc.)

**Implementation Guides:**
- Place in `Implementation/`
- Use format: `[FEATURE]_[TYPE].md` (e.g., `LOADING_SCREEN_IMPLEMENTATION.md`)
- Include code examples, before/after comparisons
- Document testing procedures

### Updating Documentation

When code changes affect documented features:
1. Update the relevant `.md` file
2. Add a "Last Updated" section if it doesn't exist
3. Note what changed and why
4. Update any affected diagrams or examples

## Index of Documentation

### Simulations & Modeling
- **NumericalTripModel_SPE_Technical_Paper.md** - Complete trip-out/trip-in physics and mathematics

### Hydraulics
- **CEMENTING_HYDRAULICS_ALIGNMENT.md** - Problem analysis and solution design
- **CEMENTING_HYDRAULICS_IMPLEMENTATION.md** - Implementation details and testing

### User Interface
- **LOADING_SCREEN_IMPLEMENTATION.md** - In-app loading overlays
- **LAUNCH_SCREEN_DOCUMENTATION.md** - App startup screen
- **LAUNCH_SCREEN_VISUAL_GUIDE.md** - Visual design specifications

### Development
- **BUILD_FIXES.md** - Common build errors and solutions

## Quick Links

- [Main README](../README.md) - Project root README
- [Contributing Guidelines](../CONTRIBUTING.md) - If exists
- [API Documentation](../API.md) - If exists
