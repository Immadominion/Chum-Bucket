/// Result class for wallet export operations
class WalletExportResult {
  final bool isSuccess;
  final String? address;
  final String? mnemonic;
  final String? privateKey;
  final String? error;
  final WalletExportType type;

  const WalletExportResult._({
    required this.isSuccess,
    this.address,
    this.mnemonic,
    this.privateKey,
    this.error,
    required this.type,
  });

  /// Success result with wallet export data
  factory WalletExportResult.success({
    required String address,
    required String privateKey,
    String? mnemonic,
  }) {
    return WalletExportResult._(
      isSuccess: true,
      address: address,
      mnemonic: mnemonic,
      privateKey: privateKey,
      type: WalletExportType.full,
    );
  }

  /// Result with only wallet address (when full export is not available)
  factory WalletExportResult.addressOnly(String address) {
    return WalletExportResult._(
      isSuccess: true,
      address: address,
      type: WalletExportType.addressOnly,
    );
  }

  /// Error result
  factory WalletExportResult.error(String errorMessage) {
    return WalletExportResult._(
      isSuccess: false,
      error: errorMessage,
      type: WalletExportType.error,
    );
  }

  /// Whether full export (private key) is available
  bool get hasFullExport => type == WalletExportType.full;

  /// Whether only address is available
  bool get hasAddressOnly => type == WalletExportType.addressOnly;

  /// Whether there was an error
  bool get hasError => type == WalletExportType.error;
}

/// Types of wallet export results
enum WalletExportType {
  /// Full export with private key and optionally mnemonic
  full,

  /// Only wallet address available
  addressOnly,

  /// Error occurred during export
  error,
}
