import 'package:flutter/material.dart';

/// Phân loại nhóm nguyên tố trong Bảng tuần hoàn.
enum ElementCategory {
  alkaliMetal,
  alkalineEarth,
  transitionMetal,
  postTransition,
  metalloid,
  reactiveNonmetal,
  halogen,
  nobleGas,
  lanthanide,
  actinide;

  String get labelVi {
    switch (this) {
      case ElementCategory.alkaliMetal:
        return 'Kim loại kiềm';
      case ElementCategory.alkalineEarth:
        return 'Kim loại kiềm thổ';
      case ElementCategory.transitionMetal:
        return 'Kim loại chuyển tiếp';
      case ElementCategory.postTransition:
        return 'Kim loại sau chuyển tiếp';
      case ElementCategory.metalloid:
        return 'Á kim';
      case ElementCategory.reactiveNonmetal:
        return 'Phi kim hoạt động';
      case ElementCategory.halogen:
        return 'Halogen';
      case ElementCategory.nobleGas:
        return 'Khí hiếm';
      case ElementCategory.lanthanide:
        return 'Họ Lantan';
      case ElementCategory.actinide:
        return 'Họ Actini';
    }
  }

  Color get color {
    switch (this) {
      case ElementCategory.alkaliMetal:
        return const Color(0xFFE57373);
      case ElementCategory.alkalineEarth:
        return const Color(0xFFFFB74D);
      case ElementCategory.transitionMetal:
        return const Color(0xFF64B5F6);
      case ElementCategory.postTransition:
        return const Color(0xFF4DB6AC);
      case ElementCategory.metalloid:
        return const Color(0xFF81C784);
      case ElementCategory.reactiveNonmetal:
        return const Color(0xFFA1887F);
      case ElementCategory.halogen:
        return const Color(0xFFBA68C8);
      case ElementCategory.nobleGas:
        return const Color(0xFF7986CB);
      case ElementCategory.lanthanide:
        return const Color(0xFFF06292);
      case ElementCategory.actinide:
        return const Color(0xFFFF8A65);
    }
  }
}

/// Thông tin đầy đủ của một nguyên tố hóa học.
class ChemicalElement {
  final int atomicNumber;
  final String symbol;
  final String nameVi;
  final String nameEn;
  final double atomicMass;

  /// Nhóm từ 1..18 (Họ Lantan & Actini có group = 3 theo IUPAC).
  final int group;

  /// Chu kỳ 1..7.
  final int period;
  final ElementCategory category;
  final String electronConfig;
  final double? electronegativity;
  final String oxidationStates;

  /// Trạng thái ở điều kiện chuẩn (Rắn, Lỏng, Khí).
  final String phaseAtStp;

  const ChemicalElement({
    required this.atomicNumber,
    required this.symbol,
    required this.nameVi,
    required this.nameEn,
    required this.atomicMass,
    required this.group,
    required this.period,
    required this.category,
    required this.electronConfig,
    required this.electronegativity,
    required this.oxidationStates,
    required this.phaseAtStp,
  });
}

/// Dữ liệu chuẩn xác đầy đủ 118 nguyên tố hóa học theo IUPAC.
const List<ChemicalElement> kChemicalElements = [
  ChemicalElement(atomicNumber: 1, symbol: 'H', nameVi: 'Hiđro', nameEn: 'Hydrogen', atomicMass: 1.008, group: 1, period: 1, category: ElementCategory.reactiveNonmetal, electronConfig: '1s¹', electronegativity: 2.20, oxidationStates: '-1, +1', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 2, symbol: 'He', nameVi: 'Heli', nameEn: 'Helium', atomicMass: 4.0026, group: 18, period: 1, category: ElementCategory.nobleGas, electronConfig: '1s²', electronegativity: null, oxidationStates: '0', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 3, symbol: 'Li', nameVi: 'Liti', nameEn: 'Lithium', atomicMass: 6.94, group: 1, period: 2, category: ElementCategory.alkaliMetal, electronConfig: '[He] 2s¹', electronegativity: 0.98, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 4, symbol: 'Be', nameVi: 'Beri', nameEn: 'Beryllium', atomicMass: 9.0122, group: 2, period: 2, category: ElementCategory.alkalineEarth, electronConfig: '[He] 2s²', electronegativity: 1.57, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 5, symbol: 'B', nameVi: 'Bo', nameEn: 'Boron', atomicMass: 10.81, group: 13, period: 2, category: ElementCategory.metalloid, electronConfig: '[He] 2s² 2p¹', electronegativity: 2.04, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 6, symbol: 'C', nameVi: 'Cacbon', nameEn: 'Carbon', atomicMass: 12.011, group: 14, period: 2, category: ElementCategory.reactiveNonmetal, electronConfig: '[He] 2s² 2p²', electronegativity: 2.55, oxidationStates: '-4, +2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 7, symbol: 'N', nameVi: 'Nitơ', nameEn: 'Nitrogen', atomicMass: 14.007, group: 15, period: 2, category: ElementCategory.reactiveNonmetal, electronConfig: '[He] 2s² 2p³', electronegativity: 3.04, oxidationStates: '-3, +1, +2, +3, +4, +5', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 8, symbol: 'O', nameVi: 'Oxi', nameEn: 'Oxygen', atomicMass: 15.999, group: 16, period: 2, category: ElementCategory.reactiveNonmetal, electronConfig: '[He] 2s² 2p⁴', electronegativity: 3.44, oxidationStates: '-2, -1', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 9, symbol: 'F', nameVi: 'Flo', nameEn: 'Fluorine', atomicMass: 18.998, group: 17, period: 2, category: ElementCategory.halogen, electronConfig: '[He] 2s² 2p⁵', electronegativity: 3.98, oxidationStates: '-1', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 10, symbol: 'Ne', nameVi: 'Neon', nameEn: 'Neon', atomicMass: 20.180, group: 18, period: 2, category: ElementCategory.nobleGas, electronConfig: '[He] 2s² 2p⁶', electronegativity: null, oxidationStates: '0', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 11, symbol: 'Na', nameVi: 'Natri', nameEn: 'Sodium', atomicMass: 22.990, group: 1, period: 3, category: ElementCategory.alkaliMetal, electronConfig: '[Ne] 3s¹', electronegativity: 0.93, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 12, symbol: 'Mg', nameVi: 'Magie', nameEn: 'Magnesium', atomicMass: 24.305, group: 2, period: 3, category: ElementCategory.alkalineEarth, electronConfig: '[Ne] 3s²', electronegativity: 1.31, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 13, symbol: 'Al', nameVi: 'Nhôm', nameEn: 'Aluminum', atomicMass: 26.982, group: 13, period: 3, category: ElementCategory.postTransition, electronConfig: '[Ne] 3s² 3p¹', electronegativity: 1.61, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 14, symbol: 'Si', nameVi: 'Silic', nameEn: 'Silicon', atomicMass: 28.085, group: 14, period: 3, category: ElementCategory.metalloid, electronConfig: '[Ne] 3s² 3p²', electronegativity: 1.90, oxidationStates: '-4, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 15, symbol: 'P', nameVi: 'Photpho', nameEn: 'Phosphorus', atomicMass: 30.974, group: 15, period: 3, category: ElementCategory.reactiveNonmetal, electronConfig: '[Ne] 3s² 3p³', electronegativity: 2.19, oxidationStates: '-3, +3, +5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 16, symbol: 'S', nameVi: 'Lưu huỳnh', nameEn: 'Sulfur', atomicMass: 32.06, group: 16, period: 3, category: ElementCategory.reactiveNonmetal, electronConfig: '[Ne] 3s² 3p⁴', electronegativity: 2.58, oxidationStates: '-2, +4, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 17, symbol: 'Cl', nameVi: 'Clo', nameEn: 'Chlorine', atomicMass: 35.45, group: 17, period: 3, category: ElementCategory.halogen, electronConfig: '[Ne] 3s² 3p⁵', electronegativity: 3.16, oxidationStates: '-1, +1, +3, +5, +7', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 18, symbol: 'Ar', nameVi: 'Argon', nameEn: 'Argon', atomicMass: 39.948, group: 18, period: 3, category: ElementCategory.nobleGas, electronConfig: '[Ne] 3s² 3p⁶', electronegativity: null, oxidationStates: '0', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 19, symbol: 'K', nameVi: 'Kali', nameEn: 'Potassium', atomicMass: 39.098, group: 1, period: 4, category: ElementCategory.alkaliMetal, electronConfig: '[Ar] 4s¹', electronegativity: 0.82, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 20, symbol: 'Ca', nameVi: 'Canxi', nameEn: 'Calcium', atomicMass: 40.078, group: 2, period: 4, category: ElementCategory.alkalineEarth, electronConfig: '[Ar] 4s²', electronegativity: 1.00, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 21, symbol: 'Sc', nameVi: 'Scandi', nameEn: 'Scandium', atomicMass: 44.956, group: 3, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d¹ 4s²', electronegativity: 1.36, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 22, symbol: 'Ti', nameVi: 'Titan', nameEn: 'Titanium', atomicMass: 47.867, group: 4, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d² 4s²', electronegativity: 1.54, oxidationStates: '+2, +3, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 23, symbol: 'V', nameVi: 'Vanadi', nameEn: 'Vanadium', atomicMass: 50.942, group: 5, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d³ 4s²', electronegativity: 1.63, oxidationStates: '+2, +3, +4, +5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 24, symbol: 'Cr', nameVi: 'Crom', nameEn: 'Chromium', atomicMass: 51.996, group: 6, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d⁵ 4s¹', electronegativity: 1.66, oxidationStates: '+2, +3, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 25, symbol: 'Mn', nameVi: 'Mangan', nameEn: 'Manganese', atomicMass: 54.938, group: 7, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d⁵ 4s²', electronegativity: 1.55, oxidationStates: '+2, +4, +7', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 26, symbol: 'Fe', nameVi: 'Sắt', nameEn: 'Iron', atomicMass: 55.845, group: 8, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d⁶ 4s²', electronegativity: 1.83, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 27, symbol: 'Co', nameVi: 'Coban', nameEn: 'Cobalt', atomicMass: 58.933, group: 9, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d⁷ 4s²', electronegativity: 1.88, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 28, symbol: 'Ni', nameVi: 'Niken', nameEn: 'Nickel', atomicMass: 58.693, group: 10, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d⁸ 4s²', electronegativity: 1.91, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 29, symbol: 'Cu', nameVi: 'Đồng', nameEn: 'Copper', atomicMass: 63.546, group: 11, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d¹⁰ 4s¹', electronegativity: 1.90, oxidationStates: '+1, +2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 30, symbol: 'Zn', nameVi: 'Kẽm', nameEn: 'Zinc', atomicMass: 65.38, group: 12, period: 4, category: ElementCategory.transitionMetal, electronConfig: '[Ar] 3d¹⁰ 4s²', electronegativity: 1.65, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 31, symbol: 'Ga', nameVi: 'Gali', nameEn: 'Gallium', atomicMass: 69.723, group: 13, period: 4, category: ElementCategory.postTransition, electronConfig: '[Ar] 3d¹⁰ 4s² 4p¹', electronegativity: 1.81, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 32, symbol: 'Ge', nameVi: 'Gemani', nameEn: 'Germanium', atomicMass: 72.630, group: 14, period: 4, category: ElementCategory.metalloid, electronConfig: '[Ar] 3d¹⁰ 4s² 4p²', electronegativity: 2.01, oxidationStates: '+2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 33, symbol: 'As', nameVi: 'Asen', nameEn: 'Arsenic', atomicMass: 74.922, group: 15, period: 4, category: ElementCategory.metalloid, electronConfig: '[Ar] 3d¹⁰ 4s² 4p³', electronegativity: 2.18, oxidationStates: '-3, +3, +5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 34, symbol: 'Se', nameVi: 'Selen', nameEn: 'Selenium', atomicMass: 78.971, group: 16, period: 4, category: ElementCategory.reactiveNonmetal, electronConfig: '[Ar] 3d¹⁰ 4s² 4p⁴', electronegativity: 2.55, oxidationStates: '-2, +4, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 35, symbol: 'Br', nameVi: 'Brom', nameEn: 'Bromine', atomicMass: 79.904, group: 17, period: 4, category: ElementCategory.halogen, electronConfig: '[Ar] 3d¹⁰ 4s² 4p⁵', electronegativity: 2.96, oxidationStates: '-1, +1, +5', phaseAtStp: 'Lỏng'),
  ChemicalElement(atomicNumber: 36, symbol: 'Kr', nameVi: 'Kripton', nameEn: 'Krypton', atomicMass: 83.798, group: 18, period: 4, category: ElementCategory.nobleGas, electronConfig: '[Ar] 3d¹⁰ 4s² 4p⁶', electronegativity: 3.00, oxidationStates: '0, +2', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 37, symbol: 'Rb', nameVi: 'Rubiđi', nameEn: 'Rubidium', atomicMass: 85.468, group: 1, period: 5, category: ElementCategory.alkaliMetal, electronConfig: '[Kr] 5s¹', electronegativity: 0.82, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 38, symbol: 'Sr', nameVi: 'Stronti', nameEn: 'Strontium', atomicMass: 87.62, group: 2, period: 5, category: ElementCategory.alkalineEarth, electronConfig: '[Kr] 5s²', electronegativity: 0.95, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 39, symbol: 'Y', nameVi: 'Ytri', nameEn: 'Yttrium', atomicMass: 88.906, group: 3, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d¹ 5s²', electronegativity: 1.22, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 40, symbol: 'Zr', nameVi: 'Ziriconi', nameEn: 'Zirconium', atomicMass: 91.224, group: 4, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d² 5s²', electronegativity: 1.33, oxidationStates: '+4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 41, symbol: 'Nb', nameVi: 'Niobi', nameEn: 'Niobium', atomicMass: 92.906, group: 5, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d⁴ 5s¹', electronegativity: 1.60, oxidationStates: '+3, +5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 42, symbol: 'Mo', nameVi: 'Molipđen', nameEn: 'Molybdenum', atomicMass: 95.95, group: 6, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d⁵ 5s¹', electronegativity: 2.16, oxidationStates: '+4, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 43, symbol: 'Tc', nameVi: 'Tecneti', nameEn: 'Technetium', atomicMass: 98.0, group: 7, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d⁵ 5s²', electronegativity: 1.90, oxidationStates: '+4, +7', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 44, symbol: 'Ru', nameVi: 'Ruteni', nameEn: 'Ruthenium', atomicMass: 101.07, group: 8, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d⁷ 5s¹', electronegativity: 2.20, oxidationStates: '+3, +4, +8', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 45, symbol: 'Rh', nameVi: 'Rođi', nameEn: 'Rhodium', atomicMass: 102.91, group: 9, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d⁸ 5s¹', electronegativity: 2.28, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 46, symbol: 'Pd', nameVi: 'Palađi', nameEn: 'Palladium', atomicMass: 106.42, group: 10, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d¹⁰', electronegativity: 2.20, oxidationStates: '+2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 47, symbol: 'Ag', nameVi: 'Bạc', nameEn: 'Silver', atomicMass: 107.87, group: 11, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d¹⁰ 5s¹', electronegativity: 1.93, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 48, symbol: 'Cd', nameVi: 'Cađimi', nameEn: 'Cadmium', atomicMass: 112.41, group: 12, period: 5, category: ElementCategory.transitionMetal, electronConfig: '[Kr] 4d¹⁰ 5s²', electronegativity: 1.69, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 49, symbol: 'In', nameVi: 'Inđi', nameEn: 'Indium', atomicMass: 114.82, group: 13, period: 5, category: ElementCategory.postTransition, electronConfig: '[Kr] 4d¹⁰ 5s² 5p¹', electronegativity: 1.78, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 50, symbol: 'Sn', nameVi: 'Thiếc', nameEn: 'Tin', atomicMass: 118.71, group: 14, period: 5, category: ElementCategory.postTransition, electronConfig: '[Kr] 4d¹⁰ 5s² 5p²', electronegativity: 1.96, oxidationStates: '+2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 51, symbol: 'Sb', nameVi: 'Antimon', nameEn: 'Antimony', atomicMass: 121.76, group: 15, period: 5, category: ElementCategory.metalloid, electronConfig: '[Kr] 4d¹⁰ 5s² 5p³', electronegativity: 2.05, oxidationStates: '-3, +3, +5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 52, symbol: 'Te', nameVi: 'Telu', nameEn: 'Tellurium', atomicMass: 127.60, group: 16, period: 5, category: ElementCategory.metalloid, electronConfig: '[Kr] 4d¹⁰ 5s² 5p⁴', electronegativity: 2.10, oxidationStates: '-2, +4, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 53, symbol: 'I', nameVi: 'Iot', nameEn: 'Iodine', atomicMass: 126.90, group: 17, period: 5, category: ElementCategory.halogen, electronConfig: '[Kr] 4d¹⁰ 5s² 5p⁵', electronegativity: 2.66, oxidationStates: '-1, +1, +5, +7', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 54, symbol: 'Xe', nameVi: 'Xenon', nameEn: 'Xenon', atomicMass: 131.29, group: 18, period: 5, category: ElementCategory.nobleGas, electronConfig: '[Kr] 4d¹⁰ 5s² 5p⁶', electronegativity: 2.60, oxidationStates: '0, +2, +4, +6', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 55, symbol: 'Cs', nameVi: 'Xesi', nameEn: 'Cesium', atomicMass: 132.91, group: 1, period: 6, category: ElementCategory.alkaliMetal, electronConfig: '[Xe] 6s¹', electronegativity: 0.79, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 56, symbol: 'Ba', nameVi: 'Bari', nameEn: 'Barium', atomicMass: 137.33, group: 2, period: 6, category: ElementCategory.alkalineEarth, electronConfig: '[Xe] 6s²', electronegativity: 0.89, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 57, symbol: 'La', nameVi: 'Lantan', nameEn: 'Lanthanum', atomicMass: 138.91, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 5d¹ 6s²', electronegativity: 1.10, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 58, symbol: 'Ce', nameVi: 'Xeri', nameEn: 'Cerium', atomicMass: 140.12, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹ 5d¹ 6s²', electronegativity: 1.12, oxidationStates: '+3, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 59, symbol: 'Pr', nameVi: 'Prazeođim', nameEn: 'Praseodymium', atomicMass: 140.91, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f³ 6s²', electronegativity: 1.13, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 60, symbol: 'Nd', nameVi: 'Neođim', nameEn: 'Neodymium', atomicMass: 144.24, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f⁴ 6s²', electronegativity: 1.14, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 61, symbol: 'Pm', nameVi: 'Prometi', nameEn: 'Promethium', atomicMass: 145.0, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f⁵ 6s²', electronegativity: 1.13, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 62, symbol: 'Sm', nameVi: 'Samari', nameEn: 'Samarium', atomicMass: 150.36, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f⁶ 6s²', electronegativity: 1.17, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 63, symbol: 'Eu', nameVi: 'Europi', nameEn: 'Europium', atomicMass: 151.96, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f⁷ 6s²', electronegativity: 1.20, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 64, symbol: 'Gd', nameVi: 'Gađolini', nameEn: 'Gadolinium', atomicMass: 157.25, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f⁷ 5d¹ 6s²', electronegativity: 1.20, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 65, symbol: 'Tb', nameVi: 'Tecbi', nameEn: 'Terbium', atomicMass: 158.93, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f⁹ 6s²', electronegativity: 1.20, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 66, symbol: 'Dy', nameVi: 'Điprozi', nameEn: 'Dysprosium', atomicMass: 162.50, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹⁰ 6s²', electronegativity: 1.22, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 67, symbol: 'Ho', nameVi: 'Honmi', nameEn: 'Holmium', atomicMass: 164.93, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹¹ 6s²', electronegativity: 1.23, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 68, symbol: 'Er', nameVi: 'Erbi', nameEn: 'Erbium', atomicMass: 167.26, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹² 6s²', electronegativity: 1.24, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 69, symbol: 'Tm', nameVi: 'Tuli', nameEn: 'Thulium', atomicMass: 168.93, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹³ 6s²', electronegativity: 1.25, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 70, symbol: 'Yb', nameVi: 'Ytecbi', nameEn: 'Ytterbium', atomicMass: 173.05, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹⁴ 6s²', electronegativity: 1.10, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 71, symbol: 'Lu', nameVi: 'Lutexi', nameEn: 'Lutetium', atomicMass: 174.97, group: 3, period: 6, category: ElementCategory.lanthanide, electronConfig: '[Xe] 4f¹⁴ 5d¹ 6s²', electronegativity: 1.27, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 72, symbol: 'Hf', nameVi: 'Hafini', nameEn: 'Hafnium', atomicMass: 178.49, group: 4, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d² 6s²', electronegativity: 1.30, oxidationStates: '+4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 73, symbol: 'Ta', nameVi: 'Tantan', nameEn: 'Tantalum', atomicMass: 180.95, group: 5, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d³ 6s²', electronegativity: 1.50, oxidationStates: '+5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 74, symbol: 'W', nameVi: 'Vonfram', nameEn: 'Tungsten', atomicMass: 183.84, group: 6, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d⁴ 6s²', electronegativity: 2.36, oxidationStates: '+4, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 75, symbol: 'Re', nameVi: 'Reni', nameEn: 'Rhenium', atomicMass: 186.21, group: 7, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d⁵ 6s²', electronegativity: 1.90, oxidationStates: '+4, +7', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 76, symbol: 'Os', nameVi: 'Osimi', nameEn: 'Osmium', atomicMass: 190.23, group: 8, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d⁶ 6s²', electronegativity: 2.20, oxidationStates: '+4, +8', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 77, symbol: 'Ir', nameVi: 'Iriđi', nameEn: 'Iridium', atomicMass: 192.22, group: 9, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d⁷ 6s²', electronegativity: 2.20, oxidationStates: '+3, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 78, symbol: 'Pt', nameVi: 'Platin', nameEn: 'Platinum', atomicMass: 195.08, group: 10, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d⁹ 6s¹', electronegativity: 2.28, oxidationStates: '+2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 79, symbol: 'Au', nameVi: 'Vàng', nameEn: 'Gold', atomicMass: 196.97, group: 11, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s¹', electronegativity: 2.54, oxidationStates: '+1, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 80, symbol: 'Hg', nameVi: 'Thủy ngân', nameEn: 'Mercury', atomicMass: 200.59, group: 12, period: 6, category: ElementCategory.transitionMetal, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s²', electronegativity: 2.00, oxidationStates: '+1, +2', phaseAtStp: 'Lỏng'),
  ChemicalElement(atomicNumber: 81, symbol: 'Tl', nameVi: 'Tali', nameEn: 'Thallium', atomicMass: 204.38, group: 13, period: 6, category: ElementCategory.postTransition, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p¹', electronegativity: 1.62, oxidationStates: '+1, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 82, symbol: 'Pb', nameVi: 'Chì', nameEn: 'Lead', atomicMass: 207.2, group: 14, period: 6, category: ElementCategory.postTransition, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p²', electronegativity: 2.33, oxidationStates: '+2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 83, symbol: 'Bi', nameVi: 'Bitmut', nameEn: 'Bismuth', atomicMass: 208.98, group: 15, period: 6, category: ElementCategory.postTransition, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p³', electronegativity: 2.02, oxidationStates: '+3, +5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 84, symbol: 'Po', nameVi: 'Poloni', nameEn: 'Polonium', atomicMass: 209.0, group: 16, period: 6, category: ElementCategory.postTransition, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p⁴', electronegativity: 2.00, oxidationStates: '+2, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 85, symbol: 'At', nameVi: 'Atatin', nameEn: 'Astatine', atomicMass: 210.0, group: 17, period: 6, category: ElementCategory.halogen, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p⁵', electronegativity: 2.20, oxidationStates: '-1, +1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 86, symbol: 'Rn', nameVi: 'Rađon', nameEn: 'Radon', atomicMass: 222.0, group: 18, period: 6, category: ElementCategory.nobleGas, electronConfig: '[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p⁶', electronegativity: 2.20, oxidationStates: '0, +2', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 87, symbol: 'Fr', nameVi: 'Franxi', nameEn: 'Francium', atomicMass: 223.0, group: 1, period: 7, category: ElementCategory.alkaliMetal, electronConfig: '[Rn] 7s¹', electronegativity: 0.70, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 88, symbol: 'Ra', nameVi: 'Rađi', nameEn: 'Radium', atomicMass: 226.0, group: 2, period: 7, category: ElementCategory.alkalineEarth, electronConfig: '[Rn] 7s²', electronegativity: 0.90, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 89, symbol: 'Ac', nameVi: 'Actini', nameEn: 'Actinium', atomicMass: 227.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 6d¹ 7s²', electronegativity: 1.10, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 90, symbol: 'Th', nameVi: 'Thori', nameEn: 'Thorium', atomicMass: 232.04, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 6d² 7s²', electronegativity: 1.30, oxidationStates: '+4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 91, symbol: 'Pa', nameVi: 'Protactini', nameEn: 'Protactinium', atomicMass: 231.04, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f² 6d¹ 7s²', electronegativity: 1.50, oxidationStates: '+5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 92, symbol: 'U', nameVi: 'Urani', nameEn: 'Uranium', atomicMass: 238.03, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f³ 6d¹ 7s²', electronegativity: 1.38, oxidationStates: '+4, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 93, symbol: 'Np', nameVi: 'Neptuni', nameEn: 'Neptunium', atomicMass: 237.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f⁴ 6d¹ 7s²', electronegativity: 1.36, oxidationStates: '+3, +4, +5, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 94, symbol: 'Pu', nameVi: 'Plutoni', nameEn: 'Plutonium', atomicMass: 244.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f⁶ 7s²', electronegativity: 1.28, oxidationStates: '+3, +4, +5, +6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 95, symbol: 'Am', nameVi: 'Amerixi', nameEn: 'Americium', atomicMass: 243.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f⁷ 7s²', electronegativity: 1.30, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 96, symbol: 'Cm', nameVi: 'Curi', nameEn: 'Curium', atomicMass: 247.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f⁷ 6d¹ 7s²', electronegativity: 1.30, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 97, symbol: 'Bk', nameVi: 'Beckeli', nameEn: 'Berkelium', atomicMass: 247.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f⁹ 7s²', electronegativity: 1.30, oxidationStates: '+3, +4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 98, symbol: 'Cf', nameVi: 'Califoni', nameEn: 'Californium', atomicMass: 251.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f¹⁰ 7s²', electronegativity: 1.30, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 99, symbol: 'Es', nameVi: 'Ensteni', nameEn: 'Einsteinium', atomicMass: 252.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f¹¹ 7s²', electronegativity: 1.30, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 100, symbol: 'Fm', nameVi: 'Fecmi', nameEn: 'Fermium', atomicMass: 257.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f¹² 7s²', electronegativity: 1.30, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 101, symbol: 'Md', nameVi: 'Menđelevi', nameEn: 'Mendelevium', atomicMass: 258.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f¹³ 7s²', electronegativity: 1.30, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 102, symbol: 'No', nameVi: 'Nobeli', nameEn: 'Nobelium', atomicMass: 259.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f¹⁴ 7s²', electronegativity: 1.30, oxidationStates: '+2, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 103, symbol: 'Lr', nameVi: 'Lorenxi', nameEn: 'Lawrencium', atomicMass: 266.0, group: 3, period: 7, category: ElementCategory.actinide, electronConfig: '[Rn] 5f¹⁴ 7s² 7p¹', electronegativity: 1.30, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 104, symbol: 'Rf', nameVi: 'Rơzơfođi', nameEn: 'Rutherfordium', atomicMass: 267.0, group: 4, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d² 7s²', electronegativity: null, oxidationStates: '+4', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 105, symbol: 'Db', nameVi: 'Đupni', nameEn: 'Dubnium', atomicMass: 268.0, group: 5, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d³ 7s²', electronegativity: null, oxidationStates: '+5', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 106, symbol: 'Sg', nameVi: 'Siboogi', nameEn: 'Seaborgium', atomicMass: 269.0, group: 6, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d⁴ 7s²', electronegativity: null, oxidationStates: '+6', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 107, symbol: 'Bh', nameVi: 'Bori', nameEn: 'Bohrium', atomicMass: 270.0, group: 7, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d⁵ 7s²', electronegativity: null, oxidationStates: '+7', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 108, symbol: 'Hs', nameVi: 'Hasi', nameEn: 'Hassium', atomicMass: 277.0, group: 8, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d⁶ 7s²', electronegativity: null, oxidationStates: '+8', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 109, symbol: 'Mt', nameVi: 'Meitneri', nameEn: 'Meitnerium', atomicMass: 278.0, group: 9, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d⁷ 7s²', electronegativity: null, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 110, symbol: 'Ds', nameVi: 'Đamstati', nameEn: 'Darmstadtium', atomicMass: 281.0, group: 10, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d⁸ 7s²', electronegativity: null, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 111, symbol: 'Rg', nameVi: 'Rơngeni', nameEn: 'Roentgenium', atomicMass: 282.0, group: 11, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d⁹ 7s²', electronegativity: null, oxidationStates: '+3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 112, symbol: 'Cn', nameVi: 'Copernixi', nameEn: 'Copernicium', atomicMass: 285.0, group: 12, period: 7, category: ElementCategory.transitionMetal, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s²', electronegativity: null, oxidationStates: '+2', phaseAtStp: 'Khí'),
  ChemicalElement(atomicNumber: 113, symbol: 'Nh', nameVi: 'Nihoni', nameEn: 'Nihonium', atomicMass: 286.0, group: 13, period: 7, category: ElementCategory.postTransition, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p¹', electronegativity: null, oxidationStates: '+1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 114, symbol: 'Fl', nameVi: 'Flerovi', nameEn: 'Flerovium', atomicMass: 289.0, group: 14, period: 7, category: ElementCategory.postTransition, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p²', electronegativity: null, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 115, symbol: 'Mc', nameVi: 'Moscovi', nameEn: 'Moscovium', atomicMass: 290.0, group: 15, period: 7, category: ElementCategory.postTransition, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p³', electronegativity: null, oxidationStates: '+1, +3', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 116, symbol: 'Lv', nameVi: 'Livermori', nameEn: 'Livermorium', atomicMass: 293.0, group: 16, period: 7, category: ElementCategory.postTransition, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p⁴', electronegativity: null, oxidationStates: '+2', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 117, symbol: 'Ts', nameVi: 'Tenessin', nameEn: 'Tennessine', atomicMass: 294.0, group: 17, period: 7, category: ElementCategory.halogen, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p⁵', electronegativity: null, oxidationStates: '-1, +1', phaseAtStp: 'Rắn'),
  ChemicalElement(atomicNumber: 118, symbol: 'Og', nameVi: 'Oganeson', nameEn: 'Oganesson', atomicMass: 294.0, group: 18, period: 7, category: ElementCategory.nobleGas, electronConfig: '[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p⁶', electronegativity: null, oxidationStates: '0, +2', phaseAtStp: 'Rắn'),
];

final Map<String, ChemicalElement> _elementsBySymbol = {
  for (final e in kChemicalElements) e.symbol: e,
};

final Map<int, ChemicalElement> _elementsByNumber = {
  for (final e in kChemicalElements) e.atomicNumber: e,
};

/// Tra cứu nguyên tố theo ký hiệu hóa học (phân biệt hoa/thường, ví dụ `'Fe'`, `'Na'`).
ChemicalElement? findElementBySymbol(String symbol) => _elementsBySymbol[symbol];

/// Tra cứu nguyên tố theo số hiệu nguyên tử Z (1..118).
ChemicalElement? findElementByNumber(int atomicNumber) =>
    _elementsByNumber[atomicNumber];
