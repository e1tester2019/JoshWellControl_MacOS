# Josh Well Control for Mac - User Guide

## Overview

Josh Well Control is a professional oil and gas well control application designed for field engineers and company managers. It combines powerful technical drilling calculations with comprehensive business management tools in a single, unified platform.

The application operates in two primary modes:
- **Field Mode** - Technical drilling operations, simulations, and well management
- **Business Mode** - Financial tracking, invoicing, payroll, and accounting (PIN-protected)

---

## Getting Started

### Navigation

The app uses a two-panel layout:
- **Sidebar** (left) - Navigation menu organized by category
- **Detail View** (right) - Main content area for the selected feature

### Quick Access

- **Command Palette** (`⌘K`) - Fast navigation to any feature, well, or action
- **Keyboard Shortcuts** (`⌘0-9`) - Quick access to frequently used views
- **Well Selector** - Toolbar dropdown to switch between wells
- **Project Selector** - Choose which project within a well to work on

---

## Field Operations

### Well & Project Setup

#### Creating Wells
1. Use the Command Palette (`⌘K`) or sidebar menu
2. Enter well name and optional pad assignment
3. Wells can be favorited for quick access or archived when inactive

#### Managing Projects
Each well can contain multiple projects (e.g., different hole sections):
1. Select a well from the toolbar
2. Create a new project or select an existing one
3. Projects can be duplicated to copy all geometry and settings
4. Lock projects to prevent accidental edits

---

### Well Geometry

#### Drill String
Define your pipe configuration from surface to bit:
1. Navigate to **Drill String** from the sidebar
2. Add sections with:
   - Start/end depth
   - Inner diameter (ID) and outer diameter (OD)
   - Capacity and displacement are calculated automatically
3. Sections can be reordered and nested

#### Annulus
Define your casing and annular geometry:
1. Navigate to **Annulus** from the sidebar
2. Add annular sections with depth ranges and dimensions
3. Used for volume calculations and hydraulic analysis

#### Surveys
Track wellbore trajectory:
1. Navigate to **Surveys** from the sidebar
2. Enter survey stations (MD, inclination, azimuth)
3. TVD and coordinates are calculated automatically
4. View trajectory in 2D or 3D visualization

#### Volume Summary
View calculated volumes based on your geometry:
- Drill string capacity
- Annular volume
- Total well volume
- Displacement volumes

---

### Fluids & Mud Management

#### Mud Check
Track mud properties and rheology:
1. Navigate to **Mud Check**
2. Record readings:
   - Mud weight (ppg)
   - Viscosity (funnel, plastic)
   - Yield point
   - Gel strengths
3. Historical tracking available

#### Mixing Calculator
Plan mud weight-up operations:
1. Enter current and target mud weights
2. Enter volumes and material properties
3. Calculator provides:
   - Required additive volumes
   - Blending ratios
   - Final volume estimates

#### Mud Placement
Define multi-layer fluid stacks in the wellbore:
1. Navigate to **Mud Placement**
2. Add fluid layers with density and volume
3. Used by simulations for accurate pressure calculations

---

### Pressure & Safety Analysis

#### Pressure Window
Define your safe operating envelope:
1. Navigate to **Pressure Window**
2. Enter TVD-based limits:
   - Pore pressure gradient
   - Fracture gradient
   - Maximum allowable ECD
3. Used to validate simulation results

#### Surge/Swab Calculator
Calculate transient pressures during pipe movement:
1. Enter pipe speed and geometry
2. Select open or closed-end configuration
3. View calculated surge/swab pressures
4. Compare against pressure window

---

### Simulations

#### Trip Simulation (Tripping Pipe Out)
Full wellbore pressure simulation for pulling pipe:

1. **Setup**
   - Ensure well geometry and mud properties are configured
   - Set pressure window limits

2. **Configure Parameters**
   - Trip speed (stands per hour)
   - Step size for numerical calculation
   - Active mud weight
   - Backfill mud weight (if different)

3. **Run Simulation**
   - View pressure curves vs. depth
   - See layer-by-layer fluid visualization
   - Check for pressure window violations
   - Red indicators show unsafe conditions

4. **Trip Optimizer**
   - Automatically calculates optimal slug parameters
   - Minimizes pressure margin while maintaining safety
   - Suggests slug volume and density

5. **Export**
   - Save simulation to library for comparison
   - Export PDF or HTML report

#### Trip In Simulation (Running Pipe)
Simulate casing or liner running operations:
1. Configure floated/non-floated conditions
2. Set pipe weight and fill parameters
3. View pressure predictions during run-in
4. Track hang-off points
5. Export HTML report

#### Trip Tracker
Step-by-step manual trip tracking:
1. Record each stand pulled/run
2. Log depth and volume changes
3. Track actual vs. calculated fill/loss

#### Trip Recording
Compare field observations against simulations:
1. Enter actual field readings
2. Compare to simulation predictions
3. Validate and improve models

#### Pump Schedule
Plan and simulate pump programs:
1. Create multi-stage pump programs
2. Set rates, volumes, and fluid properties for each stage
3. View hydraulic calculations:
   - ECD at various depths
   - Pressure drops
   - Annular velocities
4. Export HTML report

#### Cement Job
Plan cementing operations:
1. Define cement stages (lead, tail, spacers)
2. Enter slurry properties and volumes
3. Calculate displacement requirements
4. Run simulation
5. Export job plan

#### MPD (Managed Pressure Drilling)
Track ECD/ESD during MPD operations:
1. Log pressure readings with timestamps
2. View ECD trends
3. Analyze pressure variations

---

### Directional Drilling

#### Directional Dashboard
Compare actual trajectory against planned path:

1. **Import Plan**
   - Import directional plan from CSV
   - Or manually enter planned stations with limits

2. **View Comparison**
   - 2D plan view (North/East or vertical section)
   - 3D visualization with SceneKit
   - Variance table showing deviation from plan

3. **Limit Checking**
   - Define TVD, inclination, and azimuth limits
   - Color-coded indicators for limit violations
   - Real-time variance calculation

4. **Bit Projection**
   - Project ahead from last survey
   - View where current trajectory will end up

---

## Operations & Scheduling

### Look Ahead Scheduler
Plan drilling operations with vendor coordination:

1. **Job Codes**
   - Create task categories (e.g., "Run Casing", "Cement")
   - Track historical durations for better estimates

2. **Create Schedule**
   - Add tasks with estimated start/end times
   - Assign tasks to wells
   - Group by date, well, or sequence

3. **Vendor Management**
   - Assign vendors to tasks
   - Track call reminders
   - Log when calls were made

4. **Track Completion**
   - Mark tasks complete with actual times
   - System learns from actual durations

5. **Analytics**
   - View completion rates
   - Compare estimated vs. actual times

### Vendors
Manage service providers:
1. Add vendor companies with contact info
2. Store addresses and phone numbers
3. Link vendors to look-ahead tasks

---

### Equipment Management

#### Rentals
Track rental equipment on wells:

1. **Add Rental Items**
   - Equipment name, serial number, model
   - Start/end dates
   - Daily rate

2. **Track Status**
   - Not run
   - Working
   - Issues reported
   - Failed
   - Awaiting return

3. **Costs**
   - Daily rental calculation
   - Additional costs (delivery, damage, etc.)
   - Invoice tracking

4. **Transfers**
   - Move equipment between wells
   - Track transfer history

#### Equipment Registry
Master database of all equipment:
1. Maintain equipment records with serial numbers
2. Track rental history across wells
3. Log issues encountered during use
4. Generate on-location reports by pad

#### Material Transfers
Document equipment and material movements:
1. Create transfer records
2. List items being transferred
3. Specify source and destination wells
4. Generate PDF transfer documentation

---

## Business Management (PIN-Protected)

### Accessing Business Features
Business features are protected by a PIN:
1. Switch to Business Mode in the sidebar
2. Enter your PIN when prompted
3. Access financial features

---

### Income Tracking

#### Shift Calendar
Manage work rotation schedules:
1. Set up rotation patterns (e.g., 14-on/14-off)
2. Auto-generate work days from rotation
3. Set shift end reminders
4. View timeline of shifts

#### Work Days
Track billable work:
1. Select client and well
2. Enter start/end dates
3. Record mileage:
   - To location
   - From location
   - In-field driving
   - Commute (if applicable)
4. Apply day rate (or override)

#### Invoices
Generate client invoices:
1. Select client
2. Add line items:
   - Link to work days
   - Add materials or services
3. Apply rates and calculate totals
4. Generate PDF invoice
5. Track payment status

#### Clients
Manage client information:
- Company name and contact
- Billing address
- Default day rate and mileage rate
- Cost codes for accounting

---

### Expense Tracking

#### Expenses
Record business expenses:
1. Enter expense details:
   - Amount and date
   - Category
   - Description
2. Attach receipt image
3. Assign to client/well (optional)
4. View expense reports

#### Mileage Log
Track driving for tax purposes:
1. Log trips with:
   - Start and end locations
   - Distance
   - Purpose
2. Assign to client/well
3. CRA-compliant tracking
4. Mileage reports for tax filing

---

### Payroll

#### Employees
Manage employee records:
- Personal information
- Tax information
- Banking details for direct deposit

#### Pay Runs
Process payroll:
1. Create pay run for period
2. Add employees and hours
3. Calculate deductions and taxes
4. Generate pay stubs
5. Track payment

#### Pay Stubs
Individual payment records:
- Hours worked
- Rate and gross pay
- Deductions (tax, CPP, EI)
- Net pay

---

### Dividends

#### Shareholders
Manage shareholder information:
- Name and contact
- Ownership percentage
- Address for tax documents

#### Dividends
Declare and track dividends:
1. Create dividend declaration
2. Calculate distribution based on ownership
3. Record payment
4. Generate dividend statements

---

### Financial Reports

#### Company Statement
Generate financial statements:
1. Select year and quarter
2. View income, expenses, net position
3. Export PDF for accountant

#### Expense Report
Summarize expenses:
1. Filter by period
2. View by category
3. Export for tax filing

#### Accountant Export
Generate full accounting package:
- All invoices
- All expenses
- Payroll records
- Dividend records
- Ready for your accountant

---

## Handover & Communication

### Notes
Quick notes on wells:
1. Create notes from any dashboard
2. Pin important notes to top
3. Add timestamps
4. Notes sync across devices

### Tasks
Track action items:
1. Create tasks with descriptions
2. Set priority levels
3. Assign due dates
4. Mark complete when done
5. View overdue tasks

### Handover Reports
Document shift changes:
1. Compile notes and status
2. Generate handover report
3. Archive for historical reference

---

## Data & Sync

### Cloud Sync
- Data syncs automatically via iCloud
- Works across Mac, iPad, and iPhone
- Offline access with sync when connected

### Data Management
Access via Settings:
- Export data backups
- Reset specific data types
- Manage folder access for exports

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Open Command Palette |
| `⌘0-9` | Quick view access |
| `⌘N` | New item (context-aware) |
| `⌘S` | Save current work |
| `⌘P` | Print/Export PDF |

---

## Tips for Efficient Use

1. **Use Command Palette** - Press `⌘K` for the fastest navigation
2. **Favorite Active Wells** - Keep frequently accessed wells at the top
3. **Lock Completed Projects** - Prevent accidental changes to finalized work
4. **Use Trip Optimizer** - Let the app calculate optimal slug parameters
5. **Save Simulations** - Keep a library of simulations for comparison
6. **Set Pressure Windows First** - Always define safety limits before running simulations
7. **Archive Old Wells** - Keep your well list clean by archiving completed work

---

## Troubleshooting

### Simulation Shows Violations
- Check that pressure window is correctly defined
- Verify mud weights and geometry are accurate
- Use Trip Optimizer to find safer parameters

### Data Not Syncing
- Ensure iCloud is enabled in System Settings
- Check internet connection
- Force sync by closing and reopening the app

### Export Not Working
- Grant folder access permission when prompted
- Check that destination folder is writable
- Try exporting to Documents folder

---

## Support

For issues or feature requests, contact support through your organization's IT department or the app developer.
