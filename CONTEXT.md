# DocLedger - Medical Records Management Application

## Project Overview

DocLedger is a Flutter-based medical records management application designed for healthcare professionals to manage patient data efficiently with offline-first capabilities and simplified cloud synchronization.

## Current Architecture (Updated December 2024)

### **Core Structure**
```
lib/
├── core/                    # Core services and utilities
│   ├── auth/               # Authentication logic
│   ├── background/         # Background processing
│   ├── cloud/              # Cloud storage services
│   │   ├── services/       # Google Drive & CloudSave services
│   │   └── models/         # Cloud data models
│   ├── connectivity/       # Network connectivity
│   ├── data/               # Database and data management
│   │   ├── models/         # Data models (Patient, Visit, Payment)
│   │   ├── services/       # Database service & schema
│   │   └── repositories/   # Data repositories
│   ├── encryption/         # AES-256 encryption services
│   ├── services/           # Service locator and core services
│   └── sync/               # Legacy sync system (being phased out)
├── features/               # Feature modules
│   ├── auth/               # Authentication UI
│   ├── cloud_save/         # NEW: Simplified cloud save UI
│   ├── dashboard/          # Dashboard and analytics
│   ├── patients/           # Patient management
│   ├── restore/            # Data restore functionality
│   ├── shell/              # App navigation shell
│   ├── subscription/       # Subscription management
│   ├── sync/               # Legacy sync UI (being phased out)
│   ├── visits/             # Patient visits management
│   └── welcome/            # Welcome/onboarding
├── theme/                  # App theming
└── main.dart               # App entry point
```

## Key Features

### **1. Patient Management**
- **CRUD Operations**: Create, read, update, delete patient records
- **Patient Details**: Name, phone, DOB, address, emergency contact
- **Search & Filter**: Advanced search with filters and suggestions
- **Responsive UI**: Adaptive layouts for mobile and desktop

### **2. Visit Management**
- **Visit Records**: Track patient visits with diagnosis, treatment, prescriptions
- **Follow-up Scheduling**: Set and track follow-up appointments
- **Visit History**: Complete history per patient
- **Fee Tracking**: Record visit fees and payments

### **3. Payment Management**
- **Payment Records**: Track payments with multiple methods
- **Payment History**: Complete payment history per patient
- **Revenue Analytics**: Dashboard with revenue insights

### **4. Cloud Storage (NEW SIMPLIFIED SYSTEM)**
- **Auto-Save to Cloud**: Single toggle for automatic cloud saving
- **Google Drive Integration**: Encrypted backups to Google Drive
- **Simple Conflict Resolution**: Timestamp-based "most recent wins"
- **Real-time Status**: Clear status updates ("Saved 2 minutes ago")
- **Manual Save**: One-click "Save Now" button

### **5. Subscription Management**
- **Two-Tier System**: Free and Professional plans
- **Feature Comparison**: Clear feature differences
- **Upgrade Path**: Easy upgrade process
- **Usage Tracking**: Current plan status and usage

### **6. Security & Encryption**
- **AES-256 Encryption**: All cloud data encrypted
- **Device-Specific Keys**: Unique encryption per device
- **Secure Storage**: Local secure storage for credentials

## Current Implementation Status

### **✅ Completed Features**

#### **Cloud Save System (NEW)**
- **CloudSaveService**: Unified service replacing complex sync/backup
- **CloudSaveSettingsPage**: Simplified UI with 3 toggles
- **Auto-save functionality**: Debounced automatic saving
- **Manual save**: Single "Save Now" button
- **Status tracking**: Real-time status updates
- **Google Drive integration**: Encrypted cloud storage

#### **Database Layer**
- **SQLite with sync support**: Offline-first database
- **Settings storage**: Key-value settings storage
- **Migration system**: Database schema versioning
- **CRUD operations**: Full patient/visit/payment operations

#### **UI/UX Improvements**
- **Simplified settings**: 3 toggles instead of 8+ complex options
- **Modern account section**: Better Google account linking UI
- **Subscription management**: Clean subscription page
- **Responsive design**: Works on mobile and desktop

#### **Navigation & Shell**
- **Adaptive shell**: Different layouts for mobile/desktop
- **Updated navigation**: Points to new simplified settings
- **Service integration**: Proper dependency injection

### **✅ Completed - Phase 2**

#### **Legacy Sync System Removal**
- **Status**: ✅ **REMOVED**
- **Deleted Files**: 
  - `lib/core/sync/services/sync_service.dart`
  - `lib/core/sync/models/sync_models.dart`
  - `lib/features/sync/presentation/pages/sync_settings_page.dart`
  - `lib/features/sync/models/sync_settings.dart`
- **Cleaned Up**: Service locator, routes, database schema
- **Result**: Simplified codebase with single cloud save system

### **📋 Settings Configuration**

#### **Cloud Save Settings (NEW)**
```dart
// Simple 3-toggle system
- Auto-Save to Cloud: ON/OFF
- WiFi Only: ON/OFF  
- Show Notifications: ON/OFF
```

#### **Legacy Sync Settings**
```dart
// ✅ REMOVED - Complex 8+ setting system eliminated
// Now replaced with simple 3-toggle system
```

## How It Works

### **Data Flow**
1. **User creates/edits data** → Local SQLite database
2. **Auto-save triggers** → CloudSaveService detects changes
3. **Data preparation** → Export, encrypt, upload to Google Drive
4. **Status updates** → Real-time UI feedback
5. **Conflict resolution** → Automatic timestamp-based resolution

### **Service Architecture**
```
UI Layer (Pages/Widgets)
    ↓
CloudSaveService (UNIFIED)
    ↓
DatabaseService ← → GoogleDriveService
    ↓                    ↓
SQLite Database     Google Drive API
```

### **Authentication Flow**
1. **Google Sign-In** → OAuth2 authentication
2. **Token storage** → Secure local storage
3. **Drive access** → Scoped access to app folder
4. **Auto-refresh** → Automatic token renewal

### **Encryption Flow**
1. **Data export** → JSON snapshot from database
2. **Key derivation** → Device + clinic specific key
3. **AES-256 encryption** → Encrypt JSON data
4. **Cloud upload** → Encrypted file to Google Drive

## User Experience

### **Simplified Mental Model**
- **Before**: "Sync vs Backup vs Conflict Resolution"
- **After**: "Auto-save to cloud" (like Google Docs)

### **User Actions**
- **Setup**: Link Google account (one-time)
- **Daily use**: Data automatically saves to cloud
- **Manual**: "Save Now" button when needed
- **Status**: Clear feedback ("Saved 2 minutes ago")

### **Error Handling**
- **Network issues**: Automatic retry with user notification
- **Auth expired**: Clear re-authentication prompts
- **Conflicts**: Automatic resolution with audit trail

## Development Guidelines

### **Adding New Features**
1. **Follow feature-based structure**: `lib/features/feature_name/`
2. **Use service locator**: Register services in `service_locator.dart`
3. **Implement responsive UI**: Support both mobile and desktop
4. **Add to navigation**: Update both mobile and desktop shells

### **Database Changes**
1. **Update schema version**: Increment in `database_schema.dart`
2. **Add migration**: Implement in `_migrateToVersionX`
3. **Update models**: Modify data models as needed
4. **Test migrations**: Ensure backward compatibility

### **Cloud Integration**
1. **Use CloudSaveService**: Don't create new sync mechanisms
2. **Follow encryption**: All cloud data must be encrypted
3. **Handle errors gracefully**: Network issues are common
4. **Provide user feedback**: Clear status and error messages

## Testing Strategy

### **Manual Testing Checklist**
- [ ] **Account linking**: Google authentication works
- [ ] **Auto-save**: Data saves automatically after changes
- [ ] **Manual save**: "Save Now" button works
- [ ] **Status updates**: Real-time feedback is accurate
- [ ] **Offline mode**: App works without internet
- [ ] **Conflict resolution**: Handles data conflicts properly
- [ ] **Cross-device**: Data syncs between devices
- [ ] **Error recovery**: Handles network/auth errors

### **Key Test Scenarios**
1. **New user setup**: First-time Google account linking
2. **Data entry**: Create patients, visits, payments
3. **Network interruption**: Save during network issues
4. **Multi-device**: Same account on multiple devices
5. **Large datasets**: Performance with many records

## Known Issues & Limitations

### **Current Limitations**
- **WiFi detection**: Not fully implemented (always returns true)
- **Change detection**: Uses manual triggers, not database triggers
- **Notification system**: Placeholder implementation
- **Legacy cleanup**: Old sync system still exists in codebase

### **Future Improvements**
- **Real-time sync**: WebSocket-based real-time updates
- **Offline indicators**: Better offline/online status
- **Batch operations**: Optimize for large data sets
- **Advanced analytics**: More detailed usage analytics

## File Structure Reference

### **Key Files**
- **`lib/main.dart`**: App entry point and routing
- **`lib/core/services/service_locator.dart`**: Dependency injection
- **`lib/core/cloud/services/cloud_save_service.dart`**: NEW cloud save logic
- **`lib/features/cloud_save/presentation/pages/cloud_save_settings_page.dart`**: NEW settings UI
- **`lib/core/data/services/database_service.dart`**: Database operations
- **`lib/features/shell/adaptive_shell.dart`**: Navigation shell

### **Configuration Files**
- **`pubspec.yaml`**: Dependencies and app configuration
- **`CONTEXT.md`**: This file - project documentation
- **Database schema**: `lib/core/data/services/database_schema.dart`

## Deployment Notes

### **Platform Support**
- **Mobile**: Android and iOS
- **Desktop**: Linux, Windows, macOS
- **Web**: Limited (Google Drive auth issues)

### **Build Requirements**
- **Flutter SDK**: Latest stable
- **Google Services**: Configured for each platform
- **SQLite**: FFI support for desktop platforms

---

*Last updated: December 2024*
*Status: Phase 2 Complete - Legacy System Removed, Unified Cloud Save System*