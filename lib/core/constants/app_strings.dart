class AppStrings {
  AppStrings._();

  // General
  static const String appName = 'DocuScan Pro';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String delete = 'Delete';
  static const String share = 'Share';
  static const String export_ = 'Export';
  static const String done = 'Done';
  static const String next = 'Next';
  static const String back = 'Back';
  static const String ok = 'OK';
  static const String yes = 'Yes';
  static const String no = 'No';
  static const String error = 'Error';
  static const String success = 'Success';
  static const String loading = 'Loading...';
  static const String processing = 'Processing...';
  static const String retry = 'Retry';
  static const String noResults = 'No results found';

  // Home Screen
  static const String homeTitle = 'DocuScan Pro';
  static const String quickActions = 'Quick Actions';
  static const String recentDocuments = 'Recent Documents';
  static const String noRecentDocuments = 'No recent documents';
  static const String startScanning = 'Start scanning to see your documents here';

  // Scanning
  static const String scanDocument = 'Scan Document';
  static const String scanWhiteboard = 'Scan Whiteboard';
  static const String scanQrCode = 'Scan QR Code';
  static const String capturePhoto = 'Capture';
  static const String retake = 'Retake';
  static const String addPage = 'Add Page';
  static const String finishScan = 'Finish';
  static const String autoDetect = 'Auto Detect';
  static const String manualCrop = 'Manual Crop';

  // Scan Filters
  static const String filterOriginal = 'Original';
  static const String filterEnhanced = 'Enhanced';
  static const String filterGrayscale = 'Grayscale';
  static const String filterBW = 'Black & White';

  // PDF Operations
  static const String editPdf = 'Edit PDF';
  static const String mergePdf = 'Merge PDFs';
  static const String splitPdf = 'Split PDF';
  static const String compressPdf = 'Compress PDF';
  static const String rotatePage = 'Rotate';
  static const String deletePage = 'Delete Page';
  static const String reorderPages = 'Reorder Pages';
  static const String addPages = 'Add Pages';

  // Annotations
  static const String highlight = 'Highlight';
  static const String underline = 'Underline';
  static const String strikethrough = 'Strikethrough';
  static const String freehand = 'Freehand';
  static const String textNote = 'Text Note';
  static const String stickyNote = 'Sticky Note';

  // Fill & Sign
  static const String fillAndSign = 'Fill & Sign';
  static const String addSignature = 'Add Signature';
  static const String addText = 'Add Text';
  static const String addCheckmark = 'Add Checkmark';
  static const String addDate = 'Add Date';
  static const String savedSignatures = 'Saved Signatures';
  static const String drawSignature = 'Draw your signature';
  static const String typeSignature = 'Type your signature';
  static const String clearSignature = 'Clear';

  // Conversion
  static const String convertFiles = 'Convert Files';
  static const String pdfToWord = 'PDF to Word';
  static const String pdfToExcel = 'PDF to Excel';
  static const String pdfToImage = 'PDF to Image';
  static const String imageToPdf = 'Image to PDF';
  static const String wordToPdf = 'Word to PDF';
  static const String converting = 'Converting...';
  static const String conversionComplete = 'Conversion complete!';
  static const String enhancedConversion = 'Enhanced Conversion';
  static const String enhancedConversionLabel =
      'Enhanced conversion (uploads to our server, deleted within 60 s)';
  static const String enhancedConversionDesc =
      'Use cloud processing for complex layouts. Your file is uploaded to our '
      'server, converted, and deleted within 60 seconds.';
  static const String onDeviceConversionLabel =
      'On-device (private, works offline)';

  // OCR
  static const String runOcr = 'Run OCR';
  static const String extractText = 'Extract Text';
  static const String extractTable = 'Extract Table';
  static const String ocrProcessing = 'Recognizing text...';
  static const String ocrComplete = 'Text recognition complete';
  static const String copyText = 'Copy Text';
  static const String textCopied = 'Text copied to clipboard';
  static const String noTextFound = 'No text found in this document';
  static const String makeSearchablePdf = 'Make Searchable PDF';
  static const String searchablePdfCreated = 'Searchable PDF created';
  static const String ocrLanguage = 'Language';
  static const String preparingPages = 'Preparing pages...';
  static const String selectLanguage = 'Select Language';

  // Security
  static const String passwordProtect = 'Password Protect';
  static const String setPassword = 'Set Password';
  static const String confirmPassword = 'Confirm Password';
  static const String removePassword = 'Remove Password';
  static const String passwordMismatch = 'Passwords do not match';
  static const String permissions = 'Permissions';
  static const String allowPrinting = 'Allow Printing';
  static const String allowCopying = 'Allow Copying';
  static const String allowEditing = 'Allow Editing';

  // File Management
  static const String myDocuments = 'My Documents';
  static const String searchDocuments = 'Search documents...';
  static const String sortBy = 'Sort by';
  static const String sortByName = 'Name';
  static const String sortByDate = 'Date Modified';
  static const String sortBySize = 'Size';
  static const String rename = 'Rename';
  static const String moveTo = 'Move to...';
  static const String createFolder = 'Create Folder';
  static const String emptyFolder = 'This folder is empty';

  // QR Code
  static const String qrScanner = 'QR Scanner';
  static const String pointCamera = 'Point your camera at a QR code';
  static const String qrResult = 'QR Code Result';
  static const String copyResult = 'Copy';
  static const String openUrl = 'Open URL';

  // Settings
  static const String settings = 'Settings';
  static const String general = 'General';
  static const String appearance = 'Appearance';
  static const String darkMode = 'Dark Mode';
  static const String language = 'Language';
  static const String ocrLanguages = 'OCR Languages';
  static const String defaultScanFilter = 'Default Scan Filter';
  static const String storage = 'Storage';
  static const String storageUsed = 'Storage Used';
  static const String clearCache = 'Clear Cache';
  static const String about = 'About';
  static const String version = 'Version';
  static const String privacyPolicy = 'Privacy Policy';
  static const String termsOfService = 'Terms of Service';
  static const String rateApp = 'Rate App';
  static const String upgradeToPro = 'Upgrade to Pro';
  static const String removeAds = 'Remove Ads';
  static const String restorePurchases = 'Restore Purchases';

  // Errors
  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String errorFileNotFound = 'File not found.';
  static const String errorInvalidPdf = 'Invalid PDF file.';
  static const String errorPermissionDenied = 'Permission denied. Please grant access in Settings.';
  static const String errorCameraUnavailable = 'Camera is not available.';
  static const String errorNoInternet = 'No internet connection.';
  static const String errorConversionFailed = 'Conversion failed. Please try again.';
  static const String errorFileTooLarge = 'File is too large to process.';

  // Permissions
  static const String cameraPermissionTitle = 'Camera Access Required';
  static const String cameraPermissionMessage =
      'DocuScan Pro needs camera access to scan documents.';
  static const String storagePermissionTitle = 'Storage Access Required';
  static const String storagePermissionMessage =
      'DocuScan Pro needs storage access to save and manage your documents.';
}
