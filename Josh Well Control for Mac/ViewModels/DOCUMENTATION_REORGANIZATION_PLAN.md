# Documentation Reorganization Plan

## Current State
All `.md` documentation files are currently in the root `/repo` directory mixed with source code.

## Proposed Organization

Move the following files to `/repo/Documentation/`:

### Technical Papers
Move to: `/repo/Documentation/Technical/`
- `NumericalTripModel_SPE_Technical_Paper.md`
- `CEMENTING_HYDRAULICS_ALIGNMENT.md`
- `CEMENTING_HYDRAULICS_IMPLEMENTATION.md`

### Implementation Guides  
Move to: `/repo/Documentation/Implementation/`
- `LOADING_SCREEN_IMPLEMENTATION.md`
- `LAUNCH_SCREEN_DOCUMENTATION.md`
- `LAUNCH_SCREEN_VISUAL_GUIDE.md`
- `BUILD_FIXES.md`

### Keep in Root
- `README.md` - Main project README
- `LICENSE` - If exists
- `CONTRIBUTING.md` - If exists

## Benefits

1. **Cleaner root directory** - Only code and essential config files
2. **Better organization** - Docs grouped by purpose
3. **Easier to find** - Logical structure
4. **AI-friendly** - Clear documentation path for assistants

## Git Commands (for manual execution)

```bash
# Create directories
mkdir -p Documentation/Technical
mkdir -p Documentation/Implementation

# Move technical docs
git mv NumericalTripModel_SPE_Technical_Paper.md Documentation/Technical/
git mv CEMENTING_HYDRAULICS_ALIGNMENT.md Documentation/Technical/
git mv CEMENTING_HYDRAULICS_IMPLEMENTATION.md Documentation/Technical/

# Move implementation docs
git mv LOADING_SCREEN_IMPLEMENTATION.md Documentation/Implementation/
git mv LAUNCH_SCREEN_DOCUMENTATION.md Documentation/Implementation/
git mv LAUNCH_SCREEN_VISUAL_GUIDE.md Documentation/Implementation/
git mv BUILD_FIXES.md Documentation/Implementation/

# Commit
git commit -m "Reorganize documentation into Documentation/ folder structure"
```

## Update References

After moving files, update any references in:
- Code comments that link to documentation
- Other `.md` files that cross-reference
- AI assistant configuration files

## For Claude/AI Assistants

Update system prompts or configuration to:

```
When creating documentation files:
- Technical specifications → /Documentation/Technical/
- Implementation guides → /Documentation/Implementation/
- User guides → /Documentation/Guides/ (if needed)

Never create .md files in /repo root unless they are:
- README.md
- LICENSE
- CONTRIBUTING.md
- CHANGELOG.md
```

## Status

⏳ **Pending Manual Execution** - These files need to be moved using Git or Xcode file management.

The files were created during an AI coding session and should be reorganized for better project structure.
