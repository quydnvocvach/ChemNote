/// Biến số trong công thức hóa học kèm ý nghĩa tiếng Việt và đơn vị chuẩn.
class FormulaVariable {
  final String symbol;
  final String meaningVi;
  final String unit;

  const FormulaVariable({
    required this.symbol,
    required this.meaningVi,
    required this.unit,
  });
}

/// Một công thức hóa học trong sổ tay tra cứu của ChemNote.
class ChemFormula {
  final String id;
  final String title;
  final String category;
  final String expression;
  final List<FormulaVariable> variables;
  final String notes;
  final String formattedInsertText;

  const ChemFormula({
    required this.id,
    required this.title,
    required this.category,
    required this.expression,
    required this.variables,
    required this.notes,
    required this.formattedInsertText,
  });
}

/// Hằng số hóa lý thông dụng cho sinh viên Hóa học.
class ChemConstant {
  final String symbol;
  final String nameVi;
  final String value;
  final String unit;

  const ChemConstant({
    required this.symbol,
    required this.nameVi,
    required this.value,
    required this.unit,
  });
}

const List<String> kFormulaCategories = [
  'Tất cả',
  'Hóa đại cương',
  'Khí lý tưởng & Khí thực',
  'Nhiệt động lực học',
  'Động hóa học',
  'Dung dịch, Cân bằng & pH',
  'Điện hóa học',
  'Hóa phân tích & Quang phổ',
];

/// Bộ ký hiệu hóa học nhanh (nhúng trong Bảng Công cụ Hóa học).
const List<String> kChemSymbols = [
  '₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉',
  '⁺', '⁻', '²⁺', '³⁺', '²⁻',
  '→', '⇌', '↔', 'Δ', '°', '↑', '↓', '·',
  'λ⁰', 'μ⁰', 'α', 'β', 'γ', 'π', 'Σ',
];

const List<ChemConstant> kChemConstants = [
  ChemConstant(symbol: 'Nₐ', nameVi: 'Hằng số Avogadro', value: '6.022 × 10²³', unit: 'mol⁻¹'),
  ChemConstant(symbol: 'R', nameVi: 'Hằng số khí lý tưởng', value: '8.3145', unit: 'J/(mol·K)'),
  ChemConstant(symbol: 'R', nameVi: 'Hằng số khí (hệ atm)', value: '0.08206', unit: 'L·atm/(mol·K)'),
  ChemConstant(symbol: 'F', nameVi: 'Hằng số Faraday', value: '96485', unit: 'C/mol'),
  ChemConstant(symbol: 'h', nameVi: 'Hằng số Planck', value: '6.626 × 10⁻³⁴', unit: 'J·s'),
  ChemConstant(symbol: 'c', nameVi: 'Tốc độ ánh sáng chân không', value: '2.998 × 10⁸', unit: 'm/s'),
  ChemConstant(symbol: 'k_B', nameVi: 'Hằng số Boltzmann', value: '1.381 × 10⁻²³', unit: 'J/K'),
  ChemConstant(symbol: 'K_w', nameVi: 'Tích số ion của nước (25°C)', value: '1.0 × 10⁻¹⁴', unit: 'mol²/L²'),
  ChemConstant(symbol: 'V_m', nameVi: 'Thể tích mol khí ở đkc (25°C, 1 bar)', value: '24.79', unit: 'L/mol'),
  ChemConstant(symbol: 'V_m', nameVi: 'Thể tích mol khí ở đktc (0°C, 1 atm)', value: '22.414', unit: 'L/mol'),
];

const List<ChemFormula> kChemFormulas = [
  // ======================== 1. HÓA ĐẠI CƯƠNG ========================
  ChemFormula(
    id: 'gen_mol',
    title: 'Số mol chất',
    category: 'Hóa đại cương',
    expression: 'n = m / M = N / Nₐ',
    variables: [
      FormulaVariable(symbol: 'n', meaningVi: 'Số mol chất', unit: 'mol'),
      FormulaVariable(symbol: 'm', meaningVi: 'Khối lượng chất', unit: 'g'),
      FormulaVariable(symbol: 'M', meaningVi: 'Khối lượng mol phân tử', unit: 'g/mol'),
      FormulaVariable(symbol: 'N', meaningVi: 'Số hạt vi mô (nguyên tử/phân tử)', unit: 'hạt'),
    ],
    notes: 'Nₐ = 6.022 × 10²³ mol⁻¹.',
    formattedInsertText: 'n = m / M = N / Nₐ  (mol)',
  ),
  ChemFormula(
    id: 'gen_molarity',
    title: 'Nồng độ mol (C_M)',
    category: 'Hóa đại cương',
    expression: 'C_M = n / V',
    variables: [
      FormulaVariable(symbol: 'C_M', meaningVi: 'Nồng độ mol', unit: 'mol/L (M)'),
      FormulaVariable(symbol: 'n', meaningVi: 'Số mol chất tan', unit: 'mol'),
      FormulaVariable(symbol: 'V', meaningVi: 'Thể tích dung dịch', unit: 'L'),
    ],
    notes: 'Liên hệ với C%: C_M = (10 × D × C%) / M (D tính bằng g/mL).',
    formattedInsertText: 'C_M = n / V = (10 · D · C%) / M',
  ),
  ChemFormula(
    id: 'gen_mass_percent',
    title: 'Nồng độ phần trăm khối lượng (C%)',
    category: 'Hóa đại cương',
    expression: 'C% = (m_ct / m_dd) × 100%',
    variables: [
      FormulaVariable(symbol: 'C%', meaningVi: 'Nồng độ phần trăm', unit: '%'),
      FormulaVariable(symbol: 'm_ct', meaningVi: 'Khối lượng chất tan', unit: 'g'),
      FormulaVariable(symbol: 'm_dd', meaningVi: 'Khối lượng dung dịch', unit: 'g'),
    ],
    notes: 'm_dd = m_ct + m_dung_môi = V_dd × D.',
    formattedInsertText: 'C% = (m_ct / m_dd) × 100%',
  ),
  ChemFormula(
    id: 'gen_normality',
    title: 'Đương lượng & Nồng độ đương lượng (C_N)',
    category: 'Hóa đại cương',
    expression: 'Đ = M / z  ;  C_N = z · C_M = m / (Đ · V)',
    variables: [
      FormulaVariable(symbol: 'Đ', meaningVi: 'Đương lượng gam', unit: 'g/đlg'),
      FormulaVariable(symbol: 'z', meaningVi: 'Số đương lượng (số H⁺, OH⁻ hoặc e trao đổi)', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'C_N', meaningVi: 'Nồng độ đương lượng', unit: 'N (đlg/L)'),
    ],
    notes: 'Định luật đương lượng trong chuẩn độ: C_N1·V_1 = C_N2·V_2.',
    formattedInsertText: 'Đ = M / z ; C_N = z · C_M ; C_N1·V_1 = C_N2·V_2',
  ),
  ChemFormula(
    id: 'gen_photon',
    title: 'Năng lượng Photon (Planck)',
    category: 'Hóa đại cương',
    expression: 'E = h·ν = h·c / λ',
    variables: [
      FormulaVariable(symbol: 'E', meaningVi: 'Năng lượng 1 photon', unit: 'J'),
      FormulaVariable(symbol: 'h', meaningVi: 'Hằng số Planck (6.626 × 10⁻³⁴)', unit: 'J·s'),
      FormulaVariable(symbol: 'ν', meaningVi: 'Tần số bức xạ', unit: 'Hz (s⁻¹)'),
      FormulaVariable(symbol: 'λ', meaningVi: 'Bước sóng', unit: 'm'),
    ],
    notes: '1 eV = 1.602 × 10⁻¹⁹ J; 1 nm = 10⁻⁹ m.',
    formattedInsertText: 'E = h·ν = h·c / λ',
  ),
  ChemFormula(
    id: 'gen_de_broglie',
    title: 'Bước sóng de Broglie',
    category: 'Hóa đại cương',
    expression: 'λ = h / p = h / (m·v)',
    variables: [
      FormulaVariable(symbol: 'λ', meaningVi: 'Bước sóng vật chất', unit: 'm'),
      FormulaVariable(symbol: 'm', meaningVi: 'Khối lượng hạt', unit: 'kg'),
      FormulaVariable(symbol: 'v', meaningVi: 'Vận tốc hạt', unit: 'm/s'),
    ],
    notes: 'Khối lượng electron m_e = 9.109 × 10⁻³¹ kg.',
    formattedInsertText: 'λ = h / (m · v)',
  ),

  // ======================== 2. KHÍ LÝ TƯỞNG & KHÍ THỰC ========================
  ChemFormula(
    id: 'gas_ideal',
    title: 'Phương trình trạng thái khí lý tưởng (Clapeyron-Mendeleev)',
    category: 'Khí lý tưởng & Khí thực',
    expression: 'P·V = n·R·T',
    variables: [
      FormulaVariable(symbol: 'P', meaningVi: 'Áp suất khí', unit: 'atm hoặc Pa'),
      FormulaVariable(symbol: 'V', meaningVi: 'Thể tích khí', unit: 'L hoặc m³'),
      FormulaVariable(symbol: 'n', meaningVi: 'Số mol khí', unit: 'mol'),
      FormulaVariable(symbol: 'R', meaningVi: 'Hằng số khí (0.08206 L·atm/mol·K hoặc 8.314 J/mol·K)', unit: 'J/(mol·K)'),
      FormulaVariable(symbol: 'T', meaningVi: 'Nhiệt độ tuyệt đối (t°C + 273.15)', unit: 'K'),
    ],
    notes: '1 atm = 101325 Pa = 760 mmHg = 1.01325 bar.',
    formattedInsertText: 'P · V = n · R · T',
  ),
  ChemFormula(
    id: 'gas_van_der_waals',
    title: 'Phương trình khí thực Van der Waals',
    category: 'Khí lý tưởng & Khí thực',
    expression: '(P + a·n²/V²)·(V - n·b) = n·R·T',
    variables: [
      FormulaVariable(symbol: 'a', meaningVi: 'Hằng số hiệu chỉnh lực hút giữa các phân tử', unit: 'L²·atm/mol²'),
      FormulaVariable(symbol: 'b', meaningVi: 'Hằng số hiệu chỉnh thể tích riêng phân tử', unit: 'L/mol'),
    ],
    notes: 'Áp dụng khi áp suất cao hoặc nhiệt độ thấp, khí lệch khỏi trạng thái lý tưởng.',
    formattedInsertText: '(P + a·n²/V²)(V - n·b) = n·R·T',
  ),
  ChemFormula(
    id: 'gas_dalton',
    title: 'Định luật áp suất riêng phần Dalton',
    category: 'Khí lý tưởng & Khí thực',
    expression: 'P_tổng = Σ P_i  ;  P_i = x_i · P_tổng',
    variables: [
      FormulaVariable(symbol: 'P_i', meaningVi: 'Áp suất riêng phần khí i', unit: 'atm hoặc Pa'),
      FormulaVariable(symbol: 'x_i', meaningVi: 'Phần mol của khí i (n_i / n_tổng)', unit: 'không thứ nguyên'),
    ],
    notes: 'Tổng phần mol Σ x_i = 1.',
    formattedInsertText: 'P_tổng = Σ P_i ; P_i = x_i · P_tổng',
  ),
  ChemFormula(
    id: 'gas_graham',
    title: 'Định luật khuếch tán Graham',
    category: 'Khí lý tưởng & Khí thực',
    expression: 'v₁ / v₂ = √(M₂ / M₁)',
    variables: [
      FormulaVariable(symbol: 'v₁, v₂', meaningVi: 'Tốc độ khuếch tán (hoặc thoát khí) của khí 1 và 2', unit: 'm/s hoặc mol/s'),
      FormulaVariable(symbol: 'M₁, M₂', meaningVi: 'Khối lượng mol phân tử khí 1 và 2', unit: 'g/mol'),
    ],
    notes: 'Cùng điều kiện nhiệt độ và áp suất.',
    formattedInsertText: 'v₁ / v₂ = √(M₂ / M₁)',
  ),

  // ======================== 3. NHIỆT ĐỘNG LỰC HỌC ========================
  ChemFormula(
    id: 'thermo_hess',
    title: 'Hiệu ứng nhiệt phản ứng (Định luật Hess)',
    category: 'Nhiệt động lực học',
    expression: 'ΔH°_pư = Σ ΔH°_f(sản phẩm) - Σ ΔH°_f(chất đầu)',
    variables: [
      FormulaVariable(symbol: 'ΔH°_pư', meaningVi: 'Biến thiên entanpi chuẩn của phản ứng', unit: 'kJ/mol'),
      FormulaVariable(symbol: 'ΔH°_f', meaningVi: 'Nhiệt tạo thành chuẩn', unit: 'kJ/mol'),
    ],
    notes: 'ΔH < 0: phản ứng tỏa nhiệt; ΔH > 0: phản ứng thu nhiệt. ΔH°_f đơn chất bền = 0.',
    formattedInsertText: 'ΔH°_pư = Σ ΔH°_f(sp) - Σ ΔH°_f(cđ)',
  ),
  ChemFormula(
    id: 'thermo_entropy',
    title: 'Biến thiên Entropy chuẩn (ΔS°)',
    category: 'Nhiệt động lực học',
    expression: 'ΔS°_pư = Σ S°(sản phẩm) - Σ S°(chất đầu)',
    variables: [
      FormulaVariable(symbol: 'ΔS°_pư', meaningVi: 'Biến thiên entropy phản ứng', unit: 'J/(mol·K)'),
      FormulaVariable(symbol: 'S°', meaningVi: 'Entropy tuyệt đối chuẩn của chất', unit: 'J/(mol·K)'),
    ],
    notes: 'Chú ý đổi đơn vị J sang kJ (chia 1000) khi thay vào công thức ΔG.',
    formattedInsertText: 'ΔS°_pư = Σ S°(sp) - Σ S°(cđ)',
  ),
  ChemFormula(
    id: 'thermo_gibbs',
    title: 'Năng lượng tự do Gibbs (ΔG)',
    category: 'Nhiệt động lực học',
    expression: 'ΔG = ΔH - T·ΔS',
    variables: [
      FormulaVariable(symbol: 'ΔG', meaningVi: 'Biến thiên năng lượng tự do Gibbs', unit: 'kJ/mol'),
      FormulaVariable(symbol: 'ΔH', meaningVi: 'Biến thiên entanpi', unit: 'kJ/mol'),
      FormulaVariable(symbol: 'T', meaningVi: 'Nhiệt độ tuyệt đối', unit: 'K'),
      FormulaVariable(symbol: 'ΔS', meaningVi: 'Biến thiên entropy', unit: 'kJ/(mol·K)'),
    ],
    notes: 'ΔG < 0: tự diễn biến; ΔG = 0: cân bằng; ΔG > 0: không tự diễn biến.',
    formattedInsertText: 'ΔG = ΔH - T·ΔS',
  ),
  ChemFormula(
    id: 'thermo_gibbs_k',
    title: 'Liên hệ ΔG° và hằng số cân bằng K',
    category: 'Nhiệt động lực học',
    expression: 'ΔG° = -R·T·ln(K)  ;  ΔG = ΔG° + R·T·ln(Q)',
    variables: [
      FormulaVariable(symbol: 'K', meaningVi: 'Hằng số cân bằng nhiệt động', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'Q', meaningVi: 'Thương số phản ứng', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'R', meaningVi: '8.3145', unit: 'J/(mol·K)'),
    ],
    notes: 'Ở 298.15 K: ΔG° = -5.708 · log₁₀(K) (kJ/mol).',
    formattedInsertText: 'ΔG° = -R·T·ln(K)',
  ),
  ChemFormula(
    id: 'thermo_vant_hoff',
    title: 'Phương trình Van \'t Hoff',
    category: 'Nhiệt động lực học',
    expression: 'ln(K₂ / K₁) = -(ΔH° / R)·(1/T₂ - 1/T₁)',
    variables: [
      FormulaVariable(symbol: 'K₁, K₂', meaningVi: 'Hằng số cân bằng tại nhiệt độ T₁, T₂', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'ΔH°', meaningVi: 'Entanpi chuẩn phản ứng (coi không đổi trong khoảng T)', unit: 'J/mol'),
    ],
    notes: 'Dùng tính hằng số cân bằng khi thay đổi nhiệt độ.',
    formattedInsertText: 'ln(K₂/K₁) = -(ΔH°/R)·(1/T₂ - 1/T₁)',
  ),
  ChemFormula(
    id: 'thermo_clausius_clapeyron',
    title: 'Phương trình Clausius-Clapeyron',
    category: 'Nhiệt động lực học',
    expression: 'ln(P₂ / P₁) = -(ΔH_hh / R)·(1/T₂ - 1/T₁)',
    variables: [
      FormulaVariable(symbol: 'P₁, P₂', meaningVi: 'Áp suất hơi bão hòa ở T₁, T₂', unit: 'atm hoặc Pa'),
      FormulaVariable(symbol: 'ΔH_hh', meaningVi: 'Nhiệt hóa hơi mol', unit: 'J/mol'),
    ],
    notes: 'Giúp tính nhiệt độ sôi của chất lỏng ở các áp suất khác nhau.',
    formattedInsertText: 'ln(P₂/P₁) = -(ΔH_hh/R)·(1/T₂ - 1/T₁)',
  ),

  // ======================== 4. ĐỘNG HÓA HỌC ========================
  ChemFormula(
    id: 'kin_order0',
    title: 'Phản ứng bậc 0',
    category: 'Động hóa học',
    expression: '[A] = [A]₀ - k·t  ;  t₁/₂ = [A]₀ / (2k)',
    variables: [
      FormulaVariable(symbol: '[A]₀, [A]', meaningVi: 'Nồng độ chất đầu và tại thời điểm t', unit: 'mol/L'),
      FormulaVariable(symbol: 'k', meaningVi: 'Hằng số tốc độ bậc 0', unit: 'mol/(L·s)'),
      FormulaVariable(symbol: 't₁/₂', meaningVi: 'Chu kỳ bán hủy', unit: 's'),
    ],
    notes: 'Tốc độ phản ứng v = k không phụ thuộc nồng độ chất phản ứng.',
    formattedInsertText: 'Bậc 0: [A] = [A]₀ - k·t ; t₁/₂ = [A]₀/(2k)',
  ),
  ChemFormula(
    id: 'kin_order1',
    title: 'Phản ứng bậc 1',
    category: 'Động hóa học',
    expression: 'ln([A]₀ / [A]) = k·t  ;  t₁/₂ = ln(2) / k ≈ 0.693 / k',
    variables: [
      FormulaVariable(symbol: 'k', meaningVi: 'Hằng số tốc độ bậc 1', unit: 's⁻¹'),
      FormulaVariable(symbol: 't₁/₂', meaningVi: 'Chu kỳ bán hủy (không phụ thuộc [A]₀)', unit: 's'),
    ],
    notes: 'Phản ứng phân rã phóng xạ tuân theo động học bậc 1.',
    formattedInsertText: 'Bậc 1: ln([A]₀/[A]) = k·t ; t₁/₂ = 0.693/k',
  ),
  ChemFormula(
    id: 'kin_order2',
    title: 'Phản ứng bậc 2 (một chất hoặc [A]₀ = [B]₀)',
    category: 'Động hóa học',
    expression: '1/[A] - 1/[A]₀ = k·t  ;  t₁/₂ = 1 / (k·[A]₀)',
    variables: [
      FormulaVariable(symbol: 'k', meaningVi: 'Hằng số tốc độ bậc 2', unit: 'L/(mol·s)'),
      FormulaVariable(symbol: 't₁/₂', meaningVi: 'Chu kỳ bán hủy', unit: 's'),
    ],
    notes: 'Đồ thị 1/[A] theo t là đường thẳng có hệ số góc k.',
    formattedInsertText: 'Bậc 2: 1/[A] - 1/[A]₀ = k·t ; t₁/₂ = 1/(k·[A]₀)',
  ),
  ChemFormula(
    id: 'kin_arrhenius',
    title: 'Phương trình Arrhenius',
    category: 'Động hóa học',
    expression: 'k = A·exp(-E_a / (R·T))  ;  ln(k₂/k₁) = -(E_a/R)·(1/T₂ - 1/T₁)',
    variables: [
      FormulaVariable(symbol: 'E_a', meaningVi: 'Năng lượng hoạt hóa', unit: 'J/mol'),
      FormulaVariable(symbol: 'A', meaningVi: 'Thừa số trước lũy thừa (tần số va chạm)', unit: 'cùng đơn vị k'),
      FormulaVariable(symbol: 'R', meaningVi: '8.3145', unit: 'J/(mol·K)'),
    ],
    notes: 'Chất xúc tác làm giảm E_a, giúp tăng hằng số tốc độ k.',
    formattedInsertText: 'k = A·e^(-E_a/RT) ; ln(k₂/k₁) = -(E_a/R)(1/T₂ - 1/T₁)',
  ),

  // ======================== 5. DUNG DỊCH, CÂN BẰNG & pH ========================
  ChemFormula(
    id: 'eq_kc_kp',
    title: 'Liên hệ hằng số cân bằng K_p và K_c',
    category: 'Dung dịch, Cân bằng & pH',
    expression: 'K_p = K_c · (R·T)^Δn',
    variables: [
      FormulaVariable(symbol: 'K_p', meaningVi: 'Hằng số cân bằng theo áp suất riêng phần', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'K_c', meaningVi: 'Hằng số cân bằng theo nồng độ mol', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'Δn', meaningVi: 'Σ n_khí(sản phẩm) - Σ n_khí(chất đầu)', unit: 'mol'),
    ],
    notes: 'R = 0.08206 L·atm/(mol·K) khi áp suất tính theo atm.',
    formattedInsertText: 'K_p = K_c · (R·T)^Δn',
  ),
  ChemFormula(
    id: 'eq_ph_kw',
    title: 'pH, pOH và Tích số ion của nước K_w',
    category: 'Dung dịch, Cân bằng & pH',
    expression: 'pH = -log[H⁺]  ;  pOH = -log[OH⁻]  ;  pH + pOH = 14 (25°C)',
    variables: [
      FormulaVariable(symbol: '[H⁺]', meaningVi: 'Nồng độ mol ion H₃O⁺', unit: 'mol/L'),
      FormulaVariable(symbol: 'K_w', meaningVi: '[H⁺]·[OH⁻] = 10⁻¹⁴ ở 25°C', unit: 'mol²/L²'),
    ],
    notes: 'Axit yếu HA: [H⁺] ≈ √(K_a · C_a) khi C_a / K_a ≥ 100.',
    formattedInsertText: 'pH = -log[H⁺] ; pH + pOH = 14 (25°C)',
  ),
  ChemFormula(
    id: 'eq_henderson',
    title: 'Phương trình Henderson-Hasselbalch (Dung dịch đệm)',
    category: 'Dung dịch, Cân bằng & pH',
    expression: 'pH = pK_a + log([A⁻] / [HA])',
    variables: [
      FormulaVariable(symbol: 'pK_a', meaningVi: '-log(K_a) của axit yếu', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: '[A⁻]', meaningVi: 'Nồng độ bazơ liên hợp', unit: 'mol/L'),
      FormulaVariable(symbol: '[HA]', meaningVi: 'Nồng độ axit yếu', unit: 'mol/L'),
    ],
    notes: 'Với đệm bazơ: pOH = pK_b + log([BH⁺]/[B]). Vùng đệm hiệu quả: pK_a ± 1.',
    formattedInsertText: 'pH = pK_a + log([A⁻] / [HA])',
  ),
  ChemFormula(
    id: 'eq_ksp',
    title: 'Tích số tan (K_sp) của chất điện ly ít tan A_mB_n',
    category: 'Dung dịch, Cân bằng & pH',
    expression: 'K_sp = [Aⁿ⁺]^m · [Bᵐ⁻]^n = m^m · n^n · S^(m+n)',
    variables: [
      FormulaVariable(symbol: 'K_sp', meaningVi: 'Tích số tan ở nhiệt độ xác định', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'S', meaningVi: 'Độ tan mol trong nước nguyên chất', unit: 'mol/L'),
    ],
    notes: 'Kết tủa xuất hiện khi tích số ion Q_sp > K_sp.',
    formattedInsertText: 'K_sp(A_mB_n) = [Aⁿ⁺]^m · [Bᵐ⁻]^n = m^m·n^n·S^(m+n)',
  ),
  ChemFormula(
    id: 'eq_osmotic',
    title: 'Áp suất thẩm thấu (Van \'t Hoff)',
    category: 'Dung dịch, Cân bằng & pH',
    expression: 'π = i · C_M · R · T',
    variables: [
      FormulaVariable(symbol: 'π', meaningVi: 'Áp suất thẩm thấu', unit: 'atm'),
      FormulaVariable(symbol: 'i', meaningVi: 'Hệ số đẳng trương Van \'t Hoff (1 + α(ν-1))', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'C_M', meaningVi: 'Nồng độ mol dung dịch', unit: 'mol/L'),
    ],
    notes: 'Với chất không điện ly (như glucozơ, ure): i = 1.',
    formattedInsertText: 'π = i · C_M · R · T',
  ),
  ChemFormula(
    id: 'eq_raoult',
    title: 'Định luật Raoult (Áp suất hơi & Độ tăng điểm sôi/hạ điểm đông)',
    category: 'Dung dịch, Cân bằng & pH',
    expression: 'P = x_dm · P°  ;  ΔT_s = i·K_s·C_m  ;  ΔT_đ = i·K_đ·C_m',
    variables: [
      FormulaVariable(symbol: 'x_dm', meaningVi: 'Phần mol của dung môi', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'C_m', meaningVi: 'Nồng độ molan (mol chất tan / kg dung môi)', unit: 'mol/kg'),
      FormulaVariable(symbol: 'K_s, K_đ', meaningVi: 'Hằng số nghiệm sôi, nghiệm đông của dung môi', unit: 'K·kg/mol'),
    ],
    notes: 'Với nước: K_s = 0.512 K·kg/mol; K_đ = 1.86 K·kg/mol.',
    formattedInsertText: 'P = x_dm·P° ; ΔT_s = i·K_s·C_m ; ΔT_đ = i·K_đ·C_m',
  ),

  // ======================== 6. ĐIỆN HÓA HỌC ========================
  ChemFormula(
    id: 'elec_epin',
    title: 'Suất điện động chuẩn của pin điện hóa (E°_pin)',
    category: 'Điện hóa học',
    expression: 'E°_pin = E°(catot / khử) - E°(anot / oxi hóa)',
    variables: [
      FormulaVariable(symbol: 'E°_pin', meaningVi: 'Suất điện động chuẩn của pin', unit: 'V'),
      FormulaVariable(symbol: 'E°', meaningVi: 'Thế điện cực chuẩn (thế khử chuẩn)', unit: 'V'),
    ],
    notes: 'Pin tự hoạt động khi E°_pin > 0. Anot: xảy ra oxi hóa; Catot: xảy ra khử.',
    formattedInsertText: 'E°_pin = E°(catot) - E°(anot)',
  ),
  ChemFormula(
    id: 'elec_nernst',
    title: 'Phương trình Nernst',
    category: 'Điện hóa học',
    expression: 'E = E° - (R·T / n·F)·ln(Q) ≈ E° - (0.0592 / n)·log₁₀(Q)  (25°C)',
    variables: [
      FormulaVariable(symbol: 'E', meaningVi: 'Thế điện cực hoặc suất điện động ở điều kiện thực', unit: 'V'),
      FormulaVariable(symbol: 'n', meaningVi: 'Số mol electron trao đổi', unit: 'mol e'),
      FormulaVariable(symbol: 'F', meaningVi: 'Hằng số Faraday (96485)', unit: 'C/mol'),
      FormulaVariable(symbol: 'Q', meaningVi: 'Tỉ số hoạt độ/nồng độ [Kh]/[Ox] (cho thế điện cực)', unit: 'không thứ nguyên'),
    ],
    notes: 'Với cặp Ox + ne ⇌ Kh: E = E° + (0.0592/n)·log([Ox]/[Kh]) ở 25°C.',
    formattedInsertText: 'E = E° - (0.0592 / n) · log₁₀(Q)  (25°C)',
  ),
  ChemFormula(
    id: 'elec_gibbs',
    title: 'Liên hệ ΔG° và suất điện động E°',
    category: 'Điện hóa học',
    expression: 'ΔG° = -n · F · E°_pin',
    variables: [
      FormulaVariable(symbol: 'ΔG°', meaningVi: 'Biến thiên năng lượng tự do Gibbs chuẩn', unit: 'J/mol'),
      FormulaVariable(symbol: 'n', meaningVi: 'Số mol electron trao đổi', unit: 'mol'),
      FormulaVariable(symbol: 'F', meaningVi: '96485', unit: 'C/mol'),
    ],
    notes: 'Suy ra hằng số cân bằng: log₁₀(K) = (n · E°_pin) / 0.0592 ở 25°C.',
    formattedInsertText: 'ΔG° = -n · F · E°_pin',
  ),
  ChemFormula(
    id: 'elec_faraday',
    title: 'Định luật điện phân Faraday',
    category: 'Điện hóa học',
    expression: 'm = (A · I · t) / (n · F)',
    variables: [
      FormulaVariable(symbol: 'm', meaningVi: 'Khối lượng chất giải phóng ở điện cực', unit: 'g'),
      FormulaVariable(symbol: 'A', meaningVi: 'Khối lượng mol nguyên tử/chất', unit: 'g/mol'),
      FormulaVariable(symbol: 'I', meaningVi: 'Cường độ dòng điện một chiều', unit: 'A'),
      FormulaVariable(symbol: 't', meaningVi: 'Thời gian điện phân', unit: 's'),
      FormulaVariable(symbol: 'n', meaningVi: 'Số electron trao đổi của 1 mol chất', unit: 'mol e'),
    ],
    notes: 'Số mol electron trao đổi: n_e = (I · t) / F.',
    formattedInsertText: 'm = (A · I · t) / (n · F)',
  ),

  // ======================== 7. HÓA PHÂN TÍCH & QUANG PHỔ ========================
  ChemFormula(
    id: 'ana_beer_lambert',
    title: 'Định luật hấp thụ quang Beer-Lambert',
    category: 'Hóa phân tích & Quang phổ',
    expression: 'A = ε · l · c = -log₁₀(T) = log₁₀(I₀ / I)',
    variables: [
      FormulaVariable(symbol: 'A', meaningVi: 'Độ hấp thụ quang (Absorbance)', unit: 'không thứ nguyên'),
      FormulaVariable(symbol: 'ε', meaningVi: 'Hệ số hấp thụ mol', unit: 'L/(mol·cm)'),
      FormulaVariable(symbol: 'l', meaningVi: 'Bề dày cuvet (chiều dài quang trình)', unit: 'cm'),
      FormulaVariable(symbol: 'c', meaningVi: 'Nồng độ mol chất hấp thụ', unit: 'mol/L'),
      FormulaVariable(symbol: 'T', meaningVi: 'Độ truyền qua (I / I₀)', unit: 'không thứ nguyên'),
    ],
    notes: 'Tuyến tính tốt nhất trong khoảng độ hấp thụ A = 0.2 đến 0.8.',
    formattedInsertText: 'A = ε · l · c = -log₁₀(T)',
  ),
  ChemFormula(
    id: 'ana_dilution',
    title: 'Pha loãng dung dịch & Chuẩn độ cơ bản',
    category: 'Hóa phân tích & Quang phổ',
    expression: 'C₁ · V₁ = C₂ · V₂',
    variables: [
      FormulaVariable(symbol: 'C₁, C₂', meaningVi: 'Nồng độ dung dịch ban đầu và sau pha loãng', unit: 'mol/L (hoặc N)'),
      FormulaVariable(symbol: 'V₁, V₂', meaningVi: 'Thể tích tương ứng (cùng đơn vị)', unit: 'mL hoặc L'),
    ],
    notes: 'Với phản ứng chuẩn độ aA + bB → sản phẩm: (C_A·V_A)/a = (C_B·V_B)/b.',
    formattedInsertText: 'C₁ · V₁ = C₂ · V₂',
  ),
  ChemFormula(
    id: 'ana_stats',
    title: 'Độ lệch chuẩn mẫu (s) & Độ lệch chuẩn tương đối (RSD%)',
    category: 'Hóa phân tích & Quang phổ',
    expression: 's = √[ Σ(x_i - x̄)² / (N - 1) ]  ;  RSD% = (s / x̄) × 100%',
    variables: [
      FormulaVariable(symbol: 'x̄', meaningVi: 'Giá trị trung bình mẫu', unit: 'cùng đơn vị x_i'),
      FormulaVariable(symbol: 'N', meaningVi: 'Số lần đo lặp lại', unit: 'lần'),
      FormulaVariable(symbol: 's', meaningVi: 'Độ lệch chuẩn mẫu', unit: 'cùng đơn vị x_i'),
      FormulaVariable(symbol: 'RSD%', meaningVi: 'Độ lệch chuẩn tương đối (đánh giá độ lặp lại)', unit: '%'),
    ],
    notes: 'Khoảng tin cậy: μ = x̄ ± (t · s) / √N với hệ số Student t.',
    formattedInsertText: 's = √[Σ(x_i - x̄)²/(N-1)] ; RSD% = (s/x̄)×100%',
  ),
  ChemFormula(
    id: 'ana_error',
    title: 'Sai số tuyệt đối & Sai số tương đối',
    category: 'Hóa phân tích & Quang phổ',
    expression: 'Δx = |x_đo - x_thực|  ;  δ% = (Δx / x_thực) × 100%',
    variables: [
      FormulaVariable(symbol: 'Δx', meaningVi: 'Sai số tuyệt đối', unit: 'cùng đơn vị x'),
      FormulaVariable(symbol: 'δ%', meaningVi: 'Sai số tương đối', unit: '%'),
    ],
    notes: 'Đánh giá độ đúng của phép phân tích định lượng.',
    formattedInsertText: 'Δx = |x_đo - x_thực| ; δ% = (Δx / x_thực) × 100%',
  ),
];
