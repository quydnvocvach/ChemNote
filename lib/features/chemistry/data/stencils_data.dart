/// Định nghĩa danh mục khuôn vẽ & sticker hóa học cho ChemNote.
class ChemStencilDef {
  final String id;
  final String nameVi;
  final String category;

  /// Tỷ lệ khung mặc định (width / height).
  final double defaultAspectRatio;

  const ChemStencilDef({
    required this.id,
    required this.nameVi,
    required this.category,
    this.defaultAspectRatio = 1.0,
  });
}

const List<String> kStencilCategories = [
  'Tất cả',
  'Vòng hữu cơ',
  'Liên kết & Mũi tên',
  'Dụng cụ thí nghiệm',
];

const List<ChemStencilDef> kChemStencils = [
  // Vòng hữu cơ
  ChemStencilDef(
    id: 'benzene_ring',
    nameVi: 'Vòng Benzen (vòng tròn)',
    category: 'Vòng hữu cơ',
    defaultAspectRatio: 1.0,
  ),
  ChemStencilDef(
    id: 'benzene_kekule',
    nameVi: 'Vòng Benzen (Kekulé)',
    category: 'Vòng hữu cơ',
    defaultAspectRatio: 1.0,
  ),
  ChemStencilDef(
    id: 'cyclohexane_chair',
    nameVi: 'Xiclohexan (dạng ghế)',
    category: 'Vòng hữu cơ',
    defaultAspectRatio: 1.5,
  ),
  ChemStencilDef(
    id: 'cyclohexane_boat',
    nameVi: 'Xiclohexan (dạng thuyền)',
    category: 'Vòng hữu cơ',
    defaultAspectRatio: 1.5,
  ),
  ChemStencilDef(
    id: 'cyclopentane',
    nameVi: 'Vòng Xiclopentan',
    category: 'Vòng hữu cơ',
    defaultAspectRatio: 1.0,
  ),
  ChemStencilDef(
    id: 'cyclobutane',
    nameVi: 'Vòng Xiclobutan',
    category: 'Vòng hữu cơ',
    defaultAspectRatio: 1.0,
  ),

  // Liên kết & Mũi tên
  ChemStencilDef(
    id: 'wedge_bond',
    nameVi: 'Liên kết nêm đặc (Wedge)',
    category: 'Liên kết & Mũi tên',
    defaultAspectRatio: 2.0,
  ),
  ChemStencilDef(
    id: 'dash_bond',
    nameVi: 'Liên kết nêm nét đứt (Dash)',
    category: 'Liên kết & Mũi tên',
    defaultAspectRatio: 2.0,
  ),
  ChemStencilDef(
    id: 'arrow_reaction',
    nameVi: 'Mũi tên phản ứng',
    category: 'Liên kết & Mũi tên',
    defaultAspectRatio: 2.5,
  ),
  ChemStencilDef(
    id: 'arrow_equilibrium',
    nameVi: 'Mũi tên thuận nghịch',
    category: 'Liên kết & Mũi tên',
    defaultAspectRatio: 2.5,
  ),
  ChemStencilDef(
    id: 'arrow_resonance',
    nameVi: 'Mũi tên cộng hưởng',
    category: 'Liên kết & Mũi tên',
    defaultAspectRatio: 2.5,
  ),
  ChemStencilDef(
    id: 'arrow_curved',
    nameVi: 'Mũi tên cong (cơ chế)',
    category: 'Liên kết & Mũi tên',
    defaultAspectRatio: 1.6,
  ),

  // Dụng cụ thí nghiệm
  ChemStencilDef(
    id: 'erlenmeyer_flask',
    nameVi: 'Bình tam giác (Erlenmeyer)',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.8,
  ),
  ChemStencilDef(
    id: 'beaker',
    nameVi: 'Cốc thủy tinh (Beaker)',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.85,
  ),
  ChemStencilDef(
    id: 'round_bottom_flask',
    nameVi: 'Bình cầu đáy tròn',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.78,
  ),
  ChemStencilDef(
    id: 'test_tube',
    nameVi: 'Ống nghiệm',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.35,
  ),
  ChemStencilDef(
    id: 'burette',
    nameVi: 'Buret chuẩn độ',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.32,
  ),
  ChemStencilDef(
    id: 'pipette',
    nameVi: 'Pipet bầu',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.3,
  ),
  ChemStencilDef(
    id: 'condenser',
    nameVi: 'Ống sinh hàn (Liebig)',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 2.2,
  ),
  ChemStencilDef(
    id: 'bunsen_burner',
    nameVi: 'Đèn cồn / Đèn Bunsen',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.65,
  ),
  ChemStencilDef(
    id: 'funnel',
    nameVi: 'Phễu lọc',
    category: 'Dụng cụ thí nghiệm',
    defaultAspectRatio: 0.8,
  ),
];

/// Tìm định nghĩa khuôn theo [id]. Trả về null nếu không tồn tại.
ChemStencilDef? findStencilById(String id) {
  for (final s in kChemStencils) {
    if (s.id == id) return s;
  }
  return null;
}
