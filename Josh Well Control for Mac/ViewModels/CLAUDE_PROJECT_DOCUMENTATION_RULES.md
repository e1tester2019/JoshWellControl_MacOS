# Suggested Claude Project Configuration Updates

## Documentation Management Rules

Add these guidelines to your `.claude_project` or system configuration:

### File Organization Rules

```json
{
  "documentation_policy": {
    "location": "/Documentation/",
    "structure": {
      "technical_specs": "/Documentation/Technical/",
      "implementation_guides": "/Documentation/Implementation/",
      "user_guides": "/Documentation/Guides/",
      "api_docs": "/Documentation/API/"
    },
    "naming_convention": "[FEATURE]_[TYPE].md (UPPERCASE for guides)",
    "exceptions": {
      "root_allowed": ["README.md", "LICENSE", "CONTRIBUTING.md", "CHANGELOG.md"]
    }
  }
}
```

### Prompt Addition

Add to system prompt or custom instructions:

```
## Documentation Management

When creating documentation:

1. **Location:**
   - Technical specifications → `/Documentation/Technical/`
   - Implementation guides → `/Documentation/Implementation/`
   - User guides → `/Documentation/Guides/`
   - NEVER create .md files in project root except README.md

2. **Naming:**
   - Use descriptive names: `[Feature]_[Type].md`
   - Implementation guides: ALL_CAPS (e.g., `LOADING_SCREEN_IMPLEMENTATION.md`)
   - Technical papers: TitleCase (e.g., `NumericalTripModel_SPE_Technical_Paper.md`)

3. **Cross-references:**
   - Use relative paths in documentation links
   - Update references when moving files

4. **Before creating:**
   - Check if documentation already exists
   - Review `/Documentation/README.md` for organization rules

5. **After making changes:**
   - Update relevant documentation
   - Add "Last Updated" date
   - Document breaking changes clearly
```

### Custom Instructions for Code Generation

```
When suggesting new features or major changes:

1. Always create corresponding documentation in `/Documentation/`
2. For significant changes, create:
   - Implementation guide (what changed, how, why)
   - Testing checklist
   - Migration guide (if breaking)
3. Update existing docs if they reference changed code
4. Reference documentation in code comments using relative paths

Example code comment:
```swift
/// Calculates APL using unified service.
/// See: /Documentation/Technical/CEMENTING_HYDRAULICS_IMPLEMENTATION.md
func calculateAPL(...) {
```

### Tools/Scripts Integration

If you have build scripts or linters, add checks:

```bash
# Check for .md files in root (except allowed ones)
ALLOWED_ROOT_DOCS="README.md LICENSE CONTRIBUTING.md CHANGELOG.md"
ROOT_DOCS=$(find . -maxdepth 1 -name "*.md" -not -name "README.md")

if [ ! -z "$ROOT_DOCS" ]; then
  echo "Error: Documentation files found in root directory"
  echo "$ROOT_DOCS"
  echo "Move to /Documentation/ folder"
  exit 1
fi
```

## Benefits of This Configuration

1. **Consistency** - All AI assistants follow same rules
2. **Organization** - Documentation stays organized automatically
3. **Discovery** - Easier to find relevant docs
4. **Maintenance** - Clear ownership and structure
5. **Onboarding** - New developers/AIs know where to look

## Implementation Checklist

- [ ] Create `/Documentation/` folder structure
- [ ] Move existing docs (see DOCUMENTATION_REORGANIZATION_PLAN.md)
- [ ] Update `.claude_project` or equivalent configuration
- [ ] Add prompt to system instructions
- [ ] Update README.md to reference documentation
- [ ] Add pre-commit hook (optional)
- [ ] Test with next AI session to verify compliance

## Example Project Structure

```
josh-well-control/
├── Documentation/
│   ├── README.md                                    # Documentation index
│   ├── Technical/
│   │   ├── NumericalTripModel_SPE_Technical_Paper.md
│   │   ├── CEMENTING_HYDRAULICS_ALIGNMENT.md
│   │   └── CEMENTING_HYDRAULICS_IMPLEMENTATION.md
│   ├── Implementation/
│   │   ├── LOADING_SCREEN_IMPLEMENTATION.md
│   │   ├── LAUNCH_SCREEN_DOCUMENTATION.md
│   │   └── BUILD_FIXES.md
│   └── Guides/
│       └── (future user guides)
├── Sources/
│   └── (all .swift files)
├── Tests/
│   └── (all test files)
├── README.md                                        # Main README only
└── .claude_project                                  # AI configuration
```

## Notes

- This structure follows industry best practices
- Compatible with most documentation generators (MkDocs, Sphinx, etc.)
- Works well with GitHub/GitLab wikis and pages
- Scalable as project grows
