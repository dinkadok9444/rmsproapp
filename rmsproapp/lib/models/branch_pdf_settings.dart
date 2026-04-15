class BranchPdfSettings {
  final String branchId;
  final String? pdfCloudRunUrl;
  final bool useCustomPdfUrl;
  final DateTime? updatedAt;
  final String? updatedBy;

  BranchPdfSettings({
    required this.branchId,
    this.pdfCloudRunUrl,
    this.useCustomPdfUrl = false,
    this.updatedAt,
    this.updatedBy,
  });

  factory BranchPdfSettings.fromMap(Map<String, dynamic> data) {
    return BranchPdfSettings(
      branchId: data['branch_id']?.toString() ?? data['branchId']?.toString() ?? '',
      pdfCloudRunUrl: (data['pdf_cloud_run_url'] ?? data['pdfCloudRunUrl']) as String?,
      useCustomPdfUrl: (data['use_custom_pdf_url'] ?? data['useCustomPdfUrl']) == true,
      updatedAt: data['updated_at'] != null ? DateTime.tryParse(data['updated_at'].toString()) : null,
      updatedBy: (data['updated_by'] ?? data['updatedBy']) as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'pdf_cloud_run_url': pdfCloudRunUrl,
        'use_custom_pdf_url': useCustomPdfUrl,
      };
}
