/* ChemNote — Chemistry Student Toolkit Data & Vector Stencils (file:// compatible) */
(function () {
  'use strict';

  const elements = [{"z":1,"symbol":"H","nameVi":"Hiđro","nameEn":"Hydrogen","mass":1.008,"group":1,"period":1,"category":"reactiveNonmetal","config":"1s¹","en":2.2,"ox":"-1, +1","phase":"Khí"},{"z":2,"symbol":"He","nameVi":"Heli","nameEn":"Helium","mass":4.0026,"group":18,"period":1,"category":"nobleGas","config":"1s²","en":null,"ox":"0","phase":"Khí"},{"z":3,"symbol":"Li","nameVi":"Liti","nameEn":"Lithium","mass":6.94,"group":1,"period":2,"category":"alkaliMetal","config":"[He] 2s¹","en":0.98,"ox":"+1","phase":"Rắn"},{"z":4,"symbol":"Be","nameVi":"Beri","nameEn":"Beryllium","mass":9.0122,"group":2,"period":2,"category":"alkalineEarth","config":"[He] 2s²","en":1.57,"ox":"+2","phase":"Rắn"},{"z":5,"symbol":"B","nameVi":"Bo","nameEn":"Boron","mass":10.81,"group":13,"period":2,"category":"metalloid","config":"[He] 2s² 2p¹","en":2.04,"ox":"+3","phase":"Rắn"},{"z":6,"symbol":"C","nameVi":"Cacbon","nameEn":"Carbon","mass":12.011,"group":14,"period":2,"category":"reactiveNonmetal","config":"[He] 2s² 2p²","en":2.55,"ox":"-4, +2, +4","phase":"Rắn"},{"z":7,"symbol":"N","nameVi":"Nitơ","nameEn":"Nitrogen","mass":14.007,"group":15,"period":2,"category":"reactiveNonmetal","config":"[He] 2s² 2p³","en":3.04,"ox":"-3, +1, +2, +3, +4, +5","phase":"Khí"},{"z":8,"symbol":"O","nameVi":"Oxi","nameEn":"Oxygen","mass":15.999,"group":16,"period":2,"category":"reactiveNonmetal","config":"[He] 2s² 2p⁴","en":3.44,"ox":"-2, -1","phase":"Khí"},{"z":9,"symbol":"F","nameVi":"Flo","nameEn":"Fluorine","mass":18.998,"group":17,"period":2,"category":"halogen","config":"[He] 2s² 2p⁵","en":3.98,"ox":"-1","phase":"Khí"},{"z":10,"symbol":"Ne","nameVi":"Neon","nameEn":"Neon","mass":20.18,"group":18,"period":2,"category":"nobleGas","config":"[He] 2s² 2p⁶","en":null,"ox":"0","phase":"Khí"},{"z":11,"symbol":"Na","nameVi":"Natri","nameEn":"Sodium","mass":22.99,"group":1,"period":3,"category":"alkaliMetal","config":"[Ne] 3s¹","en":0.93,"ox":"+1","phase":"Rắn"},{"z":12,"symbol":"Mg","nameVi":"Magie","nameEn":"Magnesium","mass":24.305,"group":2,"period":3,"category":"alkalineEarth","config":"[Ne] 3s²","en":1.31,"ox":"+2","phase":"Rắn"},{"z":13,"symbol":"Al","nameVi":"Nhôm","nameEn":"Aluminum","mass":26.982,"group":13,"period":3,"category":"postTransition","config":"[Ne] 3s² 3p¹","en":1.61,"ox":"+3","phase":"Rắn"},{"z":14,"symbol":"Si","nameVi":"Silic","nameEn":"Silicon","mass":28.085,"group":14,"period":3,"category":"metalloid","config":"[Ne] 3s² 3p²","en":1.9,"ox":"-4, +4","phase":"Rắn"},{"z":15,"symbol":"P","nameVi":"Photpho","nameEn":"Phosphorus","mass":30.974,"group":15,"period":3,"category":"reactiveNonmetal","config":"[Ne] 3s² 3p³","en":2.19,"ox":"-3, +3, +5","phase":"Rắn"},{"z":16,"symbol":"S","nameVi":"Lưu huỳnh","nameEn":"Sulfur","mass":32.06,"group":16,"period":3,"category":"reactiveNonmetal","config":"[Ne] 3s² 3p⁴","en":2.58,"ox":"-2, +4, +6","phase":"Rắn"},{"z":17,"symbol":"Cl","nameVi":"Clo","nameEn":"Chlorine","mass":35.45,"group":17,"period":3,"category":"halogen","config":"[Ne] 3s² 3p⁵","en":3.16,"ox":"-1, +1, +3, +5, +7","phase":"Khí"},{"z":18,"symbol":"Ar","nameVi":"Argon","nameEn":"Argon","mass":39.948,"group":18,"period":3,"category":"nobleGas","config":"[Ne] 3s² 3p⁶","en":null,"ox":"0","phase":"Khí"},{"z":19,"symbol":"K","nameVi":"Kali","nameEn":"Potassium","mass":39.098,"group":1,"period":4,"category":"alkaliMetal","config":"[Ar] 4s¹","en":0.82,"ox":"+1","phase":"Rắn"},{"z":20,"symbol":"Ca","nameVi":"Canxi","nameEn":"Calcium","mass":40.078,"group":2,"period":4,"category":"alkalineEarth","config":"[Ar] 4s²","en":1,"ox":"+2","phase":"Rắn"},{"z":21,"symbol":"Sc","nameVi":"Scandi","nameEn":"Scandium","mass":44.956,"group":3,"period":4,"category":"transitionMetal","config":"[Ar] 3d¹ 4s²","en":1.36,"ox":"+3","phase":"Rắn"},{"z":22,"symbol":"Ti","nameVi":"Titan","nameEn":"Titanium","mass":47.867,"group":4,"period":4,"category":"transitionMetal","config":"[Ar] 3d² 4s²","en":1.54,"ox":"+2, +3, +4","phase":"Rắn"},{"z":23,"symbol":"V","nameVi":"Vanadi","nameEn":"Vanadium","mass":50.942,"group":5,"period":4,"category":"transitionMetal","config":"[Ar] 3d³ 4s²","en":1.63,"ox":"+2, +3, +4, +5","phase":"Rắn"},{"z":24,"symbol":"Cr","nameVi":"Crom","nameEn":"Chromium","mass":51.996,"group":6,"period":4,"category":"transitionMetal","config":"[Ar] 3d⁵ 4s¹","en":1.66,"ox":"+2, +3, +6","phase":"Rắn"},{"z":25,"symbol":"Mn","nameVi":"Mangan","nameEn":"Manganese","mass":54.938,"group":7,"period":4,"category":"transitionMetal","config":"[Ar] 3d⁵ 4s²","en":1.55,"ox":"+2, +4, +7","phase":"Rắn"},{"z":26,"symbol":"Fe","nameVi":"Sắt","nameEn":"Iron","mass":55.845,"group":8,"period":4,"category":"transitionMetal","config":"[Ar] 3d⁶ 4s²","en":1.83,"ox":"+2, +3","phase":"Rắn"},{"z":27,"symbol":"Co","nameVi":"Coban","nameEn":"Cobalt","mass":58.933,"group":9,"period":4,"category":"transitionMetal","config":"[Ar] 3d⁷ 4s²","en":1.88,"ox":"+2, +3","phase":"Rắn"},{"z":28,"symbol":"Ni","nameVi":"Niken","nameEn":"Nickel","mass":58.693,"group":10,"period":4,"category":"transitionMetal","config":"[Ar] 3d⁸ 4s²","en":1.91,"ox":"+2, +3","phase":"Rắn"},{"z":29,"symbol":"Cu","nameVi":"Đồng","nameEn":"Copper","mass":63.546,"group":11,"period":4,"category":"transitionMetal","config":"[Ar] 3d¹⁰ 4s¹","en":1.9,"ox":"+1, +2","phase":"Rắn"},{"z":30,"symbol":"Zn","nameVi":"Kẽm","nameEn":"Zinc","mass":65.38,"group":12,"period":4,"category":"transitionMetal","config":"[Ar] 3d¹⁰ 4s²","en":1.65,"ox":"+2","phase":"Rắn"},{"z":31,"symbol":"Ga","nameVi":"Gali","nameEn":"Gallium","mass":69.723,"group":13,"period":4,"category":"postTransition","config":"[Ar] 3d¹⁰ 4s² 4p¹","en":1.81,"ox":"+3","phase":"Rắn"},{"z":32,"symbol":"Ge","nameVi":"Gemani","nameEn":"Germanium","mass":72.63,"group":14,"period":4,"category":"metalloid","config":"[Ar] 3d¹⁰ 4s² 4p²","en":2.01,"ox":"+2, +4","phase":"Rắn"},{"z":33,"symbol":"As","nameVi":"Asen","nameEn":"Arsenic","mass":74.922,"group":15,"period":4,"category":"metalloid","config":"[Ar] 3d¹⁰ 4s² 4p³","en":2.18,"ox":"-3, +3, +5","phase":"Rắn"},{"z":34,"symbol":"Se","nameVi":"Selen","nameEn":"Selenium","mass":78.971,"group":16,"period":4,"category":"reactiveNonmetal","config":"[Ar] 3d¹⁰ 4s² 4p⁴","en":2.55,"ox":"-2, +4, +6","phase":"Rắn"},{"z":35,"symbol":"Br","nameVi":"Brom","nameEn":"Bromine","mass":79.904,"group":17,"period":4,"category":"halogen","config":"[Ar] 3d¹⁰ 4s² 4p⁵","en":2.96,"ox":"-1, +1, +5","phase":"Lỏng"},{"z":36,"symbol":"Kr","nameVi":"Kripton","nameEn":"Krypton","mass":83.798,"group":18,"period":4,"category":"nobleGas","config":"[Ar] 3d¹⁰ 4s² 4p⁶","en":3,"ox":"0, +2","phase":"Khí"},{"z":37,"symbol":"Rb","nameVi":"Rubiđi","nameEn":"Rubidium","mass":85.468,"group":1,"period":5,"category":"alkaliMetal","config":"[Kr] 5s¹","en":0.82,"ox":"+1","phase":"Rắn"},{"z":38,"symbol":"Sr","nameVi":"Stronti","nameEn":"Strontium","mass":87.62,"group":2,"period":5,"category":"alkalineEarth","config":"[Kr] 5s²","en":0.95,"ox":"+2","phase":"Rắn"},{"z":39,"symbol":"Y","nameVi":"Ytri","nameEn":"Yttrium","mass":88.906,"group":3,"period":5,"category":"transitionMetal","config":"[Kr] 4d¹ 5s²","en":1.22,"ox":"+3","phase":"Rắn"},{"z":40,"symbol":"Zr","nameVi":"Ziriconi","nameEn":"Zirconium","mass":91.224,"group":4,"period":5,"category":"transitionMetal","config":"[Kr] 4d² 5s²","en":1.33,"ox":"+4","phase":"Rắn"},{"z":41,"symbol":"Nb","nameVi":"Niobi","nameEn":"Niobium","mass":92.906,"group":5,"period":5,"category":"transitionMetal","config":"[Kr] 4d⁴ 5s¹","en":1.6,"ox":"+3, +5","phase":"Rắn"},{"z":42,"symbol":"Mo","nameVi":"Molipđen","nameEn":"Molybdenum","mass":95.95,"group":6,"period":5,"category":"transitionMetal","config":"[Kr] 4d⁵ 5s¹","en":2.16,"ox":"+4, +6","phase":"Rắn"},{"z":43,"symbol":"Tc","nameVi":"Tecneti","nameEn":"Technetium","mass":98,"group":7,"period":5,"category":"transitionMetal","config":"[Kr] 4d⁵ 5s²","en":1.9,"ox":"+4, +7","phase":"Rắn"},{"z":44,"symbol":"Ru","nameVi":"Ruteni","nameEn":"Ruthenium","mass":101.07,"group":8,"period":5,"category":"transitionMetal","config":"[Kr] 4d⁷ 5s¹","en":2.2,"ox":"+3, +4, +8","phase":"Rắn"},{"z":45,"symbol":"Rh","nameVi":"Rođi","nameEn":"Rhodium","mass":102.91,"group":9,"period":5,"category":"transitionMetal","config":"[Kr] 4d⁸ 5s¹","en":2.28,"ox":"+3","phase":"Rắn"},{"z":46,"symbol":"Pd","nameVi":"Palađi","nameEn":"Palladium","mass":106.42,"group":10,"period":5,"category":"transitionMetal","config":"[Kr] 4d¹⁰","en":2.2,"ox":"+2, +4","phase":"Rắn"},{"z":47,"symbol":"Ag","nameVi":"Bạc","nameEn":"Silver","mass":107.87,"group":11,"period":5,"category":"transitionMetal","config":"[Kr] 4d¹⁰ 5s¹","en":1.93,"ox":"+1","phase":"Rắn"},{"z":48,"symbol":"Cd","nameVi":"Cađimi","nameEn":"Cadmium","mass":112.41,"group":12,"period":5,"category":"transitionMetal","config":"[Kr] 4d¹⁰ 5s²","en":1.69,"ox":"+2","phase":"Rắn"},{"z":49,"symbol":"In","nameVi":"Inđi","nameEn":"Indium","mass":114.82,"group":13,"period":5,"category":"postTransition","config":"[Kr] 4d¹⁰ 5s² 5p¹","en":1.78,"ox":"+3","phase":"Rắn"},{"z":50,"symbol":"Sn","nameVi":"Thiếc","nameEn":"Tin","mass":118.71,"group":14,"period":5,"category":"postTransition","config":"[Kr] 4d¹⁰ 5s² 5p²","en":1.96,"ox":"+2, +4","phase":"Rắn"},{"z":51,"symbol":"Sb","nameVi":"Antimon","nameEn":"Antimony","mass":121.76,"group":15,"period":5,"category":"metalloid","config":"[Kr] 4d¹⁰ 5s² 5p³","en":2.05,"ox":"-3, +3, +5","phase":"Rắn"},{"z":52,"symbol":"Te","nameVi":"Telu","nameEn":"Tellurium","mass":127.6,"group":16,"period":5,"category":"metalloid","config":"[Kr] 4d¹⁰ 5s² 5p⁴","en":2.1,"ox":"-2, +4, +6","phase":"Rắn"},{"z":53,"symbol":"I","nameVi":"Iot","nameEn":"Iodine","mass":126.9,"group":17,"period":5,"category":"halogen","config":"[Kr] 4d¹⁰ 5s² 5p⁵","en":2.66,"ox":"-1, +1, +5, +7","phase":"Rắn"},{"z":54,"symbol":"Xe","nameVi":"Xenon","nameEn":"Xenon","mass":131.29,"group":18,"period":5,"category":"nobleGas","config":"[Kr] 4d¹⁰ 5s² 5p⁶","en":2.6,"ox":"0, +2, +4, +6","phase":"Khí"},{"z":55,"symbol":"Cs","nameVi":"Xesi","nameEn":"Cesium","mass":132.91,"group":1,"period":6,"category":"alkaliMetal","config":"[Xe] 6s¹","en":0.79,"ox":"+1","phase":"Rắn"},{"z":56,"symbol":"Ba","nameVi":"Bari","nameEn":"Barium","mass":137.33,"group":2,"period":6,"category":"alkalineEarth","config":"[Xe] 6s²","en":0.89,"ox":"+2","phase":"Rắn"},{"z":57,"symbol":"La","nameVi":"Lantan","nameEn":"Lanthanum","mass":138.91,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 5d¹ 6s²","en":1.1,"ox":"+3","phase":"Rắn"},{"z":58,"symbol":"Ce","nameVi":"Xeri","nameEn":"Cerium","mass":140.12,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹ 5d¹ 6s²","en":1.12,"ox":"+3, +4","phase":"Rắn"},{"z":59,"symbol":"Pr","nameVi":"Prazeođim","nameEn":"Praseodymium","mass":140.91,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f³ 6s²","en":1.13,"ox":"+3","phase":"Rắn"},{"z":60,"symbol":"Nd","nameVi":"Neođim","nameEn":"Neodymium","mass":144.24,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f⁴ 6s²","en":1.14,"ox":"+3","phase":"Rắn"},{"z":61,"symbol":"Pm","nameVi":"Prometi","nameEn":"Promethium","mass":145,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f⁵ 6s²","en":1.13,"ox":"+3","phase":"Rắn"},{"z":62,"symbol":"Sm","nameVi":"Samari","nameEn":"Samarium","mass":150.36,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f⁶ 6s²","en":1.17,"ox":"+2, +3","phase":"Rắn"},{"z":63,"symbol":"Eu","nameVi":"Europi","nameEn":"Europium","mass":151.96,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f⁷ 6s²","en":1.2,"ox":"+2, +3","phase":"Rắn"},{"z":64,"symbol":"Gd","nameVi":"Gađolini","nameEn":"Gadolinium","mass":157.25,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f⁷ 5d¹ 6s²","en":1.2,"ox":"+3","phase":"Rắn"},{"z":65,"symbol":"Tb","nameVi":"Tecbi","nameEn":"Terbium","mass":158.93,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f⁹ 6s²","en":1.2,"ox":"+3","phase":"Rắn"},{"z":66,"symbol":"Dy","nameVi":"Điprozi","nameEn":"Dysprosium","mass":162.5,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹⁰ 6s²","en":1.22,"ox":"+3","phase":"Rắn"},{"z":67,"symbol":"Ho","nameVi":"Honmi","nameEn":"Holmium","mass":164.93,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹¹ 6s²","en":1.23,"ox":"+3","phase":"Rắn"},{"z":68,"symbol":"Er","nameVi":"Erbi","nameEn":"Erbium","mass":167.26,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹² 6s²","en":1.24,"ox":"+3","phase":"Rắn"},{"z":69,"symbol":"Tm","nameVi":"Tuli","nameEn":"Thulium","mass":168.93,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹³ 6s²","en":1.25,"ox":"+3","phase":"Rắn"},{"z":70,"symbol":"Yb","nameVi":"Ytecbi","nameEn":"Ytterbium","mass":173.05,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹⁴ 6s²","en":1.1,"ox":"+2, +3","phase":"Rắn"},{"z":71,"symbol":"Lu","nameVi":"Lutexi","nameEn":"Lutetium","mass":174.97,"group":3,"period":6,"category":"lanthanide","config":"[Xe] 4f¹⁴ 5d¹ 6s²","en":1.27,"ox":"+3","phase":"Rắn"},{"z":72,"symbol":"Hf","nameVi":"Hafini","nameEn":"Hafnium","mass":178.49,"group":4,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d² 6s²","en":1.3,"ox":"+4","phase":"Rắn"},{"z":73,"symbol":"Ta","nameVi":"Tantan","nameEn":"Tantalum","mass":180.95,"group":5,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d³ 6s²","en":1.5,"ox":"+5","phase":"Rắn"},{"z":74,"symbol":"W","nameVi":"Vonfram","nameEn":"Tungsten","mass":183.84,"group":6,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d⁴ 6s²","en":2.36,"ox":"+4, +6","phase":"Rắn"},{"z":75,"symbol":"Re","nameVi":"Reni","nameEn":"Rhenium","mass":186.21,"group":7,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d⁵ 6s²","en":1.9,"ox":"+4, +7","phase":"Rắn"},{"z":76,"symbol":"Os","nameVi":"Osimi","nameEn":"Osmium","mass":190.23,"group":8,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d⁶ 6s²","en":2.2,"ox":"+4, +8","phase":"Rắn"},{"z":77,"symbol":"Ir","nameVi":"Iriđi","nameEn":"Iridium","mass":192.22,"group":9,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d⁷ 6s²","en":2.2,"ox":"+3, +4","phase":"Rắn"},{"z":78,"symbol":"Pt","nameVi":"Platin","nameEn":"Platinum","mass":195.08,"group":10,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d⁹ 6s¹","en":2.28,"ox":"+2, +4","phase":"Rắn"},{"z":79,"symbol":"Au","nameVi":"Vàng","nameEn":"Gold","mass":196.97,"group":11,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s¹","en":2.54,"ox":"+1, +3","phase":"Rắn"},{"z":80,"symbol":"Hg","nameVi":"Thủy ngân","nameEn":"Mercury","mass":200.59,"group":12,"period":6,"category":"transitionMetal","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s²","en":2,"ox":"+1, +2","phase":"Lỏng"},{"z":81,"symbol":"Tl","nameVi":"Tali","nameEn":"Thallium","mass":204.38,"group":13,"period":6,"category":"postTransition","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p¹","en":1.62,"ox":"+1, +3","phase":"Rắn"},{"z":82,"symbol":"Pb","nameVi":"Chì","nameEn":"Lead","mass":207.2,"group":14,"period":6,"category":"postTransition","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p²","en":2.33,"ox":"+2, +4","phase":"Rắn"},{"z":83,"symbol":"Bi","nameVi":"Bitmut","nameEn":"Bismuth","mass":208.98,"group":15,"period":6,"category":"postTransition","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p³","en":2.02,"ox":"+3, +5","phase":"Rắn"},{"z":84,"symbol":"Po","nameVi":"Poloni","nameEn":"Polonium","mass":209,"group":16,"period":6,"category":"postTransition","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p⁴","en":2,"ox":"+2, +4","phase":"Rắn"},{"z":85,"symbol":"At","nameVi":"Atatin","nameEn":"Astatine","mass":210,"group":17,"period":6,"category":"halogen","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p⁵","en":2.2,"ox":"-1, +1","phase":"Rắn"},{"z":86,"symbol":"Rn","nameVi":"Rađon","nameEn":"Radon","mass":222,"group":18,"period":6,"category":"nobleGas","config":"[Xe] 4f¹⁴ 5d¹⁰ 6s² 6p⁶","en":2.2,"ox":"0, +2","phase":"Khí"},{"z":87,"symbol":"Fr","nameVi":"Franxi","nameEn":"Francium","mass":223,"group":1,"period":7,"category":"alkaliMetal","config":"[Rn] 7s¹","en":0.7,"ox":"+1","phase":"Rắn"},{"z":88,"symbol":"Ra","nameVi":"Rađi","nameEn":"Radium","mass":226,"group":2,"period":7,"category":"alkalineEarth","config":"[Rn] 7s²","en":0.9,"ox":"+2","phase":"Rắn"},{"z":89,"symbol":"Ac","nameVi":"Actini","nameEn":"Actinium","mass":227,"group":3,"period":7,"category":"actinide","config":"[Rn] 6d¹ 7s²","en":1.1,"ox":"+3","phase":"Rắn"},{"z":90,"symbol":"Th","nameVi":"Thori","nameEn":"Thorium","mass":232.04,"group":3,"period":7,"category":"actinide","config":"[Rn] 6d² 7s²","en":1.3,"ox":"+4","phase":"Rắn"},{"z":91,"symbol":"Pa","nameVi":"Protactini","nameEn":"Protactinium","mass":231.04,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f² 6d¹ 7s²","en":1.5,"ox":"+5","phase":"Rắn"},{"z":92,"symbol":"U","nameVi":"Urani","nameEn":"Uranium","mass":238.03,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f³ 6d¹ 7s²","en":1.38,"ox":"+4, +6","phase":"Rắn"},{"z":93,"symbol":"Np","nameVi":"Neptuni","nameEn":"Neptunium","mass":237,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f⁴ 6d¹ 7s²","en":1.36,"ox":"+3, +4, +5, +6","phase":"Rắn"},{"z":94,"symbol":"Pu","nameVi":"Plutoni","nameEn":"Plutonium","mass":244,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f⁶ 7s²","en":1.28,"ox":"+3, +4, +5, +6","phase":"Rắn"},{"z":95,"symbol":"Am","nameVi":"Amerixi","nameEn":"Americium","mass":243,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f⁷ 7s²","en":1.3,"ox":"+3","phase":"Rắn"},{"z":96,"symbol":"Cm","nameVi":"Curi","nameEn":"Curium","mass":247,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f⁷ 6d¹ 7s²","en":1.3,"ox":"+3","phase":"Rắn"},{"z":97,"symbol":"Bk","nameVi":"Beckeli","nameEn":"Berkelium","mass":247,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f⁹ 7s²","en":1.3,"ox":"+3, +4","phase":"Rắn"},{"z":98,"symbol":"Cf","nameVi":"Califoni","nameEn":"Californium","mass":251,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f¹⁰ 7s²","en":1.3,"ox":"+3","phase":"Rắn"},{"z":99,"symbol":"Es","nameVi":"Ensteni","nameEn":"Einsteinium","mass":252,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f¹¹ 7s²","en":1.3,"ox":"+3","phase":"Rắn"},{"z":100,"symbol":"Fm","nameVi":"Fecmi","nameEn":"Fermium","mass":257,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f¹² 7s²","en":1.3,"ox":"+3","phase":"Rắn"},{"z":101,"symbol":"Md","nameVi":"Menđelevi","nameEn":"Mendelevium","mass":258,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f¹³ 7s²","en":1.3,"ox":"+2, +3","phase":"Rắn"},{"z":102,"symbol":"No","nameVi":"Nobeli","nameEn":"Nobelium","mass":259,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f¹⁴ 7s²","en":1.3,"ox":"+2, +3","phase":"Rắn"},{"z":103,"symbol":"Lr","nameVi":"Lorenxi","nameEn":"Lawrencium","mass":266,"group":3,"period":7,"category":"actinide","config":"[Rn] 5f¹⁴ 7s² 7p¹","en":1.3,"ox":"+3","phase":"Rắn"},{"z":104,"symbol":"Rf","nameVi":"Rơzơfođi","nameEn":"Rutherfordium","mass":267,"group":4,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d² 7s²","en":null,"ox":"+4","phase":"Rắn"},{"z":105,"symbol":"Db","nameVi":"Đupni","nameEn":"Dubnium","mass":268,"group":5,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d³ 7s²","en":null,"ox":"+5","phase":"Rắn"},{"z":106,"symbol":"Sg","nameVi":"Siboogi","nameEn":"Seaborgium","mass":269,"group":6,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d⁴ 7s²","en":null,"ox":"+6","phase":"Rắn"},{"z":107,"symbol":"Bh","nameVi":"Bori","nameEn":"Bohrium","mass":270,"group":7,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d⁵ 7s²","en":null,"ox":"+7","phase":"Rắn"},{"z":108,"symbol":"Hs","nameVi":"Hasi","nameEn":"Hassium","mass":277,"group":8,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d⁶ 7s²","en":null,"ox":"+8","phase":"Rắn"},{"z":109,"symbol":"Mt","nameVi":"Meitneri","nameEn":"Meitnerium","mass":278,"group":9,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d⁷ 7s²","en":null,"ox":"+3","phase":"Rắn"},{"z":110,"symbol":"Ds","nameVi":"Đamstati","nameEn":"Darmstadtium","mass":281,"group":10,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d⁸ 7s²","en":null,"ox":"+2","phase":"Rắn"},{"z":111,"symbol":"Rg","nameVi":"Rơngeni","nameEn":"Roentgenium","mass":282,"group":11,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d⁹ 7s²","en":null,"ox":"+3","phase":"Rắn"},{"z":112,"symbol":"Cn","nameVi":"Copernixi","nameEn":"Copernicium","mass":285,"group":12,"period":7,"category":"transitionMetal","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s²","en":null,"ox":"+2","phase":"Khí"},{"z":113,"symbol":"Nh","nameVi":"Nihoni","nameEn":"Nihonium","mass":286,"group":13,"period":7,"category":"postTransition","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p¹","en":null,"ox":"+1","phase":"Rắn"},{"z":114,"symbol":"Fl","nameVi":"Flerovi","nameEn":"Flerovium","mass":289,"group":14,"period":7,"category":"postTransition","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p²","en":null,"ox":"+2","phase":"Rắn"},{"z":115,"symbol":"Mc","nameVi":"Moscovi","nameEn":"Moscovium","mass":290,"group":15,"period":7,"category":"postTransition","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p³","en":null,"ox":"+1, +3","phase":"Rắn"},{"z":116,"symbol":"Lv","nameVi":"Livermori","nameEn":"Livermorium","mass":293,"group":16,"period":7,"category":"postTransition","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p⁴","en":null,"ox":"+2","phase":"Rắn"},{"z":117,"symbol":"Ts","nameVi":"Tenessin","nameEn":"Tennessine","mass":294,"group":17,"period":7,"category":"halogen","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p⁵","en":null,"ox":"-1, +1","phase":"Rắn"},{"z":118,"symbol":"Og","nameVi":"Oganeson","nameEn":"Oganesson","mass":294,"group":18,"period":7,"category":"nobleGas","config":"[Rn] 5f¹⁴ 6d¹⁰ 7s² 7p⁶","en":null,"ox":"0, +2","phase":"Rắn"}];

  const formulas = [{"id":"gen_mol","title":"Số mol chất","category":"Hóa đại cương","expression":"n = m / M = N / Nₐ","variables":[{"sym":"n","desc":"Số mol chất","unit":"mol"},{"sym":"m","desc":"Khối lượng chất","unit":"g"},{"sym":"M","desc":"Khối lượng mol phân tử","unit":"g/mol"},{"sym":"N","desc":"Số hạt vi mô (nguyên tử/phân tử)","unit":"hạt"}],"notes":"Nₐ = 6.022 × 10²³ mol⁻¹.","insertText":"n = m / M = N / Nₐ  (mol)"},{"id":"gen_molarity","title":"Nồng độ mol (C_M)","category":"Hóa đại cương","expression":"C_M = n / V","variables":[{"sym":"C_M","desc":"Nồng độ mol","unit":"mol/L (M)"},{"sym":"n","desc":"Số mol chất tan","unit":"mol"},{"sym":"V","desc":"Thể tích dung dịch","unit":"L"}],"notes":"Liên hệ với C%: C_M = (10 × D × C%) / M (D tính bằng g/mL).","insertText":"C_M = n / V = (10 · D · C%) / M"},{"id":"gen_mass_percent","title":"Nồng độ phần trăm khối lượng (C%)","category":"Hóa đại cương","expression":"C% = (m_ct / m_dd) × 100%","variables":[{"sym":"C%","desc":"Nồng độ phần trăm","unit":"%"},{"sym":"m_ct","desc":"Khối lượng chất tan","unit":"g"},{"sym":"m_dd","desc":"Khối lượng dung dịch","unit":"g"}],"notes":"m_dd = m_ct + m_dung_môi = V_dd × D.","insertText":"C% = (m_ct / m_dd) × 100%"},{"id":"gen_normality","title":"Đương lượng \u0026 Nồng độ đương lượng (C_N)","category":"Hóa đại cương","expression":"Đ = M / z  ;  C_N = z · C_M = m / (Đ · V)","variables":[{"sym":"Đ","desc":"Đương lượng gam","unit":"g/đlg"},{"sym":"z","desc":"Số đương lượng (số H⁺, OH⁻ hoặc e trao đổi)","unit":"không thứ nguyên"},{"sym":"C_N","desc":"Nồng độ đương lượng","unit":"N (đlg/L)"}],"notes":"Định luật đương lượng trong chuẩn độ: C_N1·V_1 = C_N2·V_2.","insertText":"Đ = M / z ; C_N = z · C_M ; C_N1·V_1 = C_N2·V_2"},{"id":"gen_photon","title":"Năng lượng Photon (Planck)","category":"Hóa đại cương","expression":"E = h·ν = h·c / λ","variables":[{"sym":"E","desc":"Năng lượng 1 photon","unit":"J"},{"sym":"h","desc":"Hằng số Planck (6.626 × 10⁻³⁴)","unit":"J·s"},{"sym":"ν","desc":"Tần số bức xạ","unit":"Hz (s⁻¹)"},{"sym":"λ","desc":"Bước sóng","unit":"m"}],"notes":"1 eV = 1.602 × 10⁻¹⁹ J; 1 nm = 10⁻⁹ m.","insertText":"E = h·ν = h·c / λ"},{"id":"gen_de_broglie","title":"Bước sóng de Broglie","category":"Hóa đại cương","expression":"λ = h / p = h / (m·v)","variables":[{"sym":"λ","desc":"Bước sóng vật chất","unit":"m"},{"sym":"m","desc":"Khối lượng hạt","unit":"kg"},{"sym":"v","desc":"Vận tốc hạt","unit":"m/s"}],"notes":"Khối lượng electron m_e = 9.109 × 10⁻³¹ kg.","insertText":"λ = h / (m · v)"},{"id":"gas_ideal","title":"Phương trình trạng thái khí lý tưởng (Clapeyron-Mendeleev)","category":"Khí lý tưởng \u0026 Khí thực","expression":"P·V = n·R·T","variables":[{"sym":"P","desc":"Áp suất khí","unit":"atm hoặc Pa"},{"sym":"V","desc":"Thể tích khí","unit":"L hoặc m³"},{"sym":"n","desc":"Số mol khí","unit":"mol"},{"sym":"R","desc":"Hằng số khí (0.08206 L·atm/mol·K hoặc 8.314 J/mol·K)","unit":"J/(mol·K)"},{"sym":"T","desc":"Nhiệt độ tuyệt đối (t°C + 273.15)","unit":"K"}],"notes":"1 atm = 101325 Pa = 760 mmHg = 1.01325 bar.","insertText":"P · V = n · R · T"},{"id":"gas_van_der_waals","title":"Phương trình khí thực Van der Waals","category":"Khí lý tưởng \u0026 Khí thực","expression":"(P + a·n²/V²)·(V - n·b) = n·R·T","variables":[{"sym":"a","desc":"Hằng số hiệu chỉnh lực hút giữa các phân tử","unit":"L²·atm/mol²"},{"sym":"b","desc":"Hằng số hiệu chỉnh thể tích riêng phân tử","unit":"L/mol"}],"notes":"Áp dụng khi áp suất cao hoặc nhiệt độ thấp, khí lệch khỏi trạng thái lý tưởng.","insertText":"(P + a·n²/V²)(V - n·b) = n·R·T"},{"id":"gas_dalton","title":"Định luật áp suất riêng phần Dalton","category":"Khí lý tưởng \u0026 Khí thực","expression":"P_tổng = Σ P_i  ;  P_i = x_i · P_tổng","variables":[{"sym":"P_i","desc":"Áp suất riêng phần khí i","unit":"atm hoặc Pa"},{"sym":"x_i","desc":"Phần mol của khí i (n_i / n_tổng)","unit":"không thứ nguyên"}],"notes":"Tổng phần mol Σ x_i = 1.","insertText":"P_tổng = Σ P_i ; P_i = x_i · P_tổng"},{"id":"gas_graham","title":"Định luật khuếch tán Graham","category":"Khí lý tưởng \u0026 Khí thực","expression":"v₁ / v₂ = √(M₂ / M₁)","variables":[{"sym":"v₁, v₂","desc":"Tốc độ khuếch tán (hoặc thoát khí) của khí 1 và 2","unit":"m/s hoặc mol/s"},{"sym":"M₁, M₂","desc":"Khối lượng mol phân tử khí 1 và 2","unit":"g/mol"}],"notes":"Cùng điều kiện nhiệt độ và áp suất.","insertText":"v₁ / v₂ = √(M₂ / M₁)"},{"id":"thermo_hess","title":"Hiệu ứng nhiệt phản ứng (Định luật Hess)","category":"Nhiệt động lực học","expression":"ΔH°_pư = Σ ΔH°_f(sản phẩm) - Σ ΔH°_f(chất đầu)","variables":[{"sym":"ΔH°_pư","desc":"Biến thiên entanpi chuẩn của phản ứng","unit":"kJ/mol"},{"sym":"ΔH°_f","desc":"Nhiệt tạo thành chuẩn","unit":"kJ/mol"}],"notes":"ΔH \u003c 0: phản ứng tỏa nhiệt; ΔH \u003e 0: phản ứng thu nhiệt. ΔH°_f đơn chất bền = 0.","insertText":"ΔH°_pư = Σ ΔH°_f(sp) - Σ ΔH°_f(cđ)"},{"id":"thermo_entropy","title":"Biến thiên Entropy chuẩn (ΔS°)","category":"Nhiệt động lực học","expression":"ΔS°_pư = Σ S°(sản phẩm) - Σ S°(chất đầu)","variables":[{"sym":"ΔS°_pư","desc":"Biến thiên entropy phản ứng","unit":"J/(mol·K)"},{"sym":"S°","desc":"Entropy tuyệt đối chuẩn của chất","unit":"J/(mol·K)"}],"notes":"Chú ý đổi đơn vị J sang kJ (chia 1000) khi thay vào công thức ΔG.","insertText":"ΔS°_pư = Σ S°(sp) - Σ S°(cđ)"},{"id":"thermo_gibbs","title":"Năng lượng tự do Gibbs (ΔG)","category":"Nhiệt động lực học","expression":"ΔG = ΔH - T·ΔS","variables":[{"sym":"ΔG","desc":"Biến thiên năng lượng tự do Gibbs","unit":"kJ/mol"},{"sym":"ΔH","desc":"Biến thiên entanpi","unit":"kJ/mol"},{"sym":"T","desc":"Nhiệt độ tuyệt đối","unit":"K"},{"sym":"ΔS","desc":"Biến thiên entropy","unit":"kJ/(mol·K)"}],"notes":"ΔG \u003c 0: tự diễn biến; ΔG = 0: cân bằng; ΔG \u003e 0: không tự diễn biến.","insertText":"ΔG = ΔH - T·ΔS"},{"id":"thermo_gibbs_k","title":"Liên hệ ΔG° và hằng số cân bằng K","category":"Nhiệt động lực học","expression":"ΔG° = -R·T·ln(K)  ;  ΔG = ΔG° + R·T·ln(Q)","variables":[{"sym":"K","desc":"Hằng số cân bằng nhiệt động","unit":"không thứ nguyên"},{"sym":"Q","desc":"Thương số phản ứng","unit":"không thứ nguyên"},{"sym":"R","desc":"8.3145","unit":"J/(mol·K)"}],"notes":"Ở 298.15 K: ΔG° = -5.708 · log₁₀(K) (kJ/mol).","insertText":"ΔG° = -R·T·ln(K)"},{"id":"thermo_vant_hoff","title":"Phương trình Van \u0027t Hoff","category":"Nhiệt động lực học","expression":"ln(K₂ / K₁) = -(ΔH° / R)·(1/T₂ - 1/T₁)","variables":[{"sym":"K₁, K₂","desc":"Hằng số cân bằng tại nhiệt độ T₁, T₂","unit":"không thứ nguyên"},{"sym":"ΔH°","desc":"Entanpi chuẩn phản ứng (coi không đổi trong khoảng T)","unit":"J/mol"}],"notes":"Dùng tính hằng số cân bằng khi thay đổi nhiệt độ.","insertText":"ln(K₂/K₁) = -(ΔH°/R)·(1/T₂ - 1/T₁)"},{"id":"thermo_clausius_clapeyron","title":"Phương trình Clausius-Clapeyron","category":"Nhiệt động lực học","expression":"ln(P₂ / P₁) = -(ΔH_hh / R)·(1/T₂ - 1/T₁)","variables":[{"sym":"P₁, P₂","desc":"Áp suất hơi bão hòa ở T₁, T₂","unit":"atm hoặc Pa"},{"sym":"ΔH_hh","desc":"Nhiệt hóa hơi mol","unit":"J/mol"}],"notes":"Giúp tính nhiệt độ sôi của chất lỏng ở các áp suất khác nhau.","insertText":"ln(P₂/P₁) = -(ΔH_hh/R)·(1/T₂ - 1/T₁)"},{"id":"kin_order0","title":"Phản ứng bậc 0","category":"Động hóa học","expression":"[A] = [A]₀ - k·t  ;  t₁/₂ = [A]₀ / (2k)","variables":[{"sym":"[A]₀, [A]","desc":"Nồng độ chất đầu và tại thời điểm t","unit":"mol/L"},{"sym":"k","desc":"Hằng số tốc độ bậc 0","unit":"mol/(L·s)"},{"sym":"t₁/₂","desc":"Chu kỳ bán hủy","unit":"s"}],"notes":"Tốc độ phản ứng v = k không phụ thuộc nồng độ chất phản ứng.","insertText":"Bậc 0: [A] = [A]₀ - k·t ; t₁/₂ = [A]₀/(2k)"},{"id":"kin_order1","title":"Phản ứng bậc 1","category":"Động hóa học","expression":"ln([A]₀ / [A]) = k·t  ;  t₁/₂ = ln(2) / k ≈ 0.693 / k","variables":[{"sym":"k","desc":"Hằng số tốc độ bậc 1","unit":"s⁻¹"},{"sym":"t₁/₂","desc":"Chu kỳ bán hủy (không phụ thuộc [A]₀)","unit":"s"}],"notes":"Phản ứng phân rã phóng xạ tuân theo động học bậc 1.","insertText":"Bậc 1: ln([A]₀/[A]) = k·t ; t₁/₂ = 0.693/k"},{"id":"kin_order2","title":"Phản ứng bậc 2 (một chất hoặc [A]₀ = [B]₀)","category":"Động hóa học","expression":"1/[A] - 1/[A]₀ = k·t  ;  t₁/₂ = 1 / (k·[A]₀)","variables":[{"sym":"k","desc":"Hằng số tốc độ bậc 2","unit":"L/(mol·s)"},{"sym":"t₁/₂","desc":"Chu kỳ bán hủy","unit":"s"}],"notes":"Đồ thị 1/[A] theo t là đường thẳng có hệ số góc k.","insertText":"Bậc 2: 1/[A] - 1/[A]₀ = k·t ; t₁/₂ = 1/(k·[A]₀)"},{"id":"kin_arrhenius","title":"Phương trình Arrhenius","category":"Động hóa học","expression":"k = A·exp(-E_a / (R·T))  ;  ln(k₂/k₁) = -(E_a/R)·(1/T₂ - 1/T₁)","variables":[{"sym":"E_a","desc":"Năng lượng hoạt hóa","unit":"J/mol"},{"sym":"A","desc":"Thừa số trước lũy thừa (tần số va chạm)","unit":"cùng đơn vị k"},{"sym":"R","desc":"8.3145","unit":"J/(mol·K)"}],"notes":"Chất xúc tác làm giảm E_a, giúp tăng hằng số tốc độ k.","insertText":"k = A·e^(-E_a/RT) ; ln(k₂/k₁) = -(E_a/R)(1/T₂ - 1/T₁)"},{"id":"eq_kc_kp","title":"Liên hệ hằng số cân bằng K_p và K_c","category":"Dung dịch, Cân bằng \u0026 pH","expression":"K_p = K_c · (R·T)^Δn","variables":[{"sym":"K_p","desc":"Hằng số cân bằng theo áp suất riêng phần","unit":"không thứ nguyên"},{"sym":"K_c","desc":"Hằng số cân bằng theo nồng độ mol","unit":"không thứ nguyên"},{"sym":"Δn","desc":"Σ n_khí(sản phẩm) - Σ n_khí(chất đầu)","unit":"mol"}],"notes":"R = 0.08206 L·atm/(mol·K) khi áp suất tính theo atm.","insertText":"K_p = K_c · (R·T)^Δn"},{"id":"eq_ph_kw","title":"pH, pOH và Tích số ion của nước K_w","category":"Dung dịch, Cân bằng \u0026 pH","expression":"pH = -log[H⁺]  ;  pOH = -log[OH⁻]  ;  pH + pOH = 14 (25°C)","variables":[{"sym":"[H⁺]","desc":"Nồng độ mol ion H₃O⁺","unit":"mol/L"},{"sym":"K_w","desc":"[H⁺]·[OH⁻] = 10⁻¹⁴ ở 25°C","unit":"mol²/L²"}],"notes":"Axit yếu HA: [H⁺] ≈ √(K_a · C_a) khi C_a / K_a ≥ 100.","insertText":"pH = -log[H⁺] ; pH + pOH = 14 (25°C)"},{"id":"eq_henderson","title":"Phương trình Henderson-Hasselbalch (Dung dịch đệm)","category":"Dung dịch, Cân bằng \u0026 pH","expression":"pH = pK_a + log([A⁻] / [HA])","variables":[{"sym":"pK_a","desc":"-log(K_a) của axit yếu","unit":"không thứ nguyên"},{"sym":"[A⁻]","desc":"Nồng độ bazơ liên hợp","unit":"mol/L"},{"sym":"[HA]","desc":"Nồng độ axit yếu","unit":"mol/L"}],"notes":"Với đệm bazơ: pOH = pK_b + log([BH⁺]/[B]). Vùng đệm hiệu quả: pK_a ± 1.","insertText":"pH = pK_a + log([A⁻] / [HA])"},{"id":"eq_ksp","title":"Tích số tan (K_sp) của chất điện ly ít tan A_mB_n","category":"Dung dịch, Cân bằng \u0026 pH","expression":"K_sp = [Aⁿ⁺]^m · [Bᵐ⁻]^n = m^m · n^n · S^(m+n)","variables":[{"sym":"K_sp","desc":"Tích số tan ở nhiệt độ xác định","unit":"không thứ nguyên"},{"sym":"S","desc":"Độ tan mol trong nước nguyên chất","unit":"mol/L"}],"notes":"Kết tủa xuất hiện khi tích số ion Q_sp \u003e K_sp.","insertText":"K_sp(A_mB_n) = [Aⁿ⁺]^m · [Bᵐ⁻]^n = m^m·n^n·S^(m+n)"},{"id":"eq_osmotic","title":"Áp suất thẩm thấu (Van \u0027t Hoff)","category":"Dung dịch, Cân bằng \u0026 pH","expression":"π = i · C_M · R · T","variables":[{"sym":"π","desc":"Áp suất thẩm thấu","unit":"atm"},{"sym":"i","desc":"Hệ số đẳng trương Van \u0027t Hoff (1 + α(ν-1))","unit":"không thứ nguyên"},{"sym":"C_M","desc":"Nồng độ mol dung dịch","unit":"mol/L"}],"notes":"Với chất không điện ly (như glucozơ, ure): i = 1.","insertText":"π = i · C_M · R · T"},{"id":"eq_raoult","title":"Định luật Raoult (Áp suất hơi \u0026 Độ tăng điểm sôi/hạ điểm đông)","category":"Dung dịch, Cân bằng \u0026 pH","expression":"P = x_dm · P°  ;  ΔT_s = i·K_s·C_m  ;  ΔT_đ = i·K_đ·C_m","variables":[{"sym":"x_dm","desc":"Phần mol của dung môi","unit":"không thứ nguyên"},{"sym":"C_m","desc":"Nồng độ molan (mol chất tan / kg dung môi)","unit":"mol/kg"},{"sym":"K_s, K_đ","desc":"Hằng số nghiệm sôi, nghiệm đông của dung môi","unit":"K·kg/mol"}],"notes":"Với nước: K_s = 0.512 K·kg/mol; K_đ = 1.86 K·kg/mol.","insertText":"P = x_dm·P° ; ΔT_s = i·K_s·C_m ; ΔT_đ = i·K_đ·C_m"},{"id":"elec_epin","title":"Suất điện động chuẩn của pin điện hóa (E°_pin)","category":"Điện hóa học","expression":"E°_pin = E°(catot / khử) - E°(anot / oxi hóa)","variables":[{"sym":"E°_pin","desc":"Suất điện động chuẩn của pin","unit":"V"},{"sym":"E°","desc":"Thế điện cực chuẩn (thế khử chuẩn)","unit":"V"}],"notes":"Pin tự hoạt động khi E°_pin \u003e 0. Anot: xảy ra oxi hóa; Catot: xảy ra khử.","insertText":"E°_pin = E°(catot) - E°(anot)"},{"id":"elec_nernst","title":"Phương trình Nernst","category":"Điện hóa học","expression":"E = E° - (R·T / n·F)·ln(Q) ≈ E° - (0.0592 / n)·log₁₀(Q)  (25°C)","variables":[{"sym":"E","desc":"Thế điện cực hoặc suất điện động ở điều kiện thực","unit":"V"},{"sym":"n","desc":"Số mol electron trao đổi","unit":"mol e"},{"sym":"F","desc":"Hằng số Faraday (96485)","unit":"C/mol"},{"sym":"Q","desc":"Tỉ số hoạt độ/nồng độ [Kh]/[Ox] (cho thế điện cực)","unit":"không thứ nguyên"}],"notes":"Với cặp Ox + ne ⇌ Kh: E = E° + (0.0592/n)·log([Ox]/[Kh]) ở 25°C.","insertText":"E = E° - (0.0592 / n) · log₁₀(Q)  (25°C)"},{"id":"elec_gibbs","title":"Liên hệ ΔG° và suất điện động E°","category":"Điện hóa học","expression":"ΔG° = -n · F · E°_pin","variables":[{"sym":"ΔG°","desc":"Biến thiên năng lượng tự do Gibbs chuẩn","unit":"J/mol"},{"sym":"n","desc":"Số mol electron trao đổi","unit":"mol"},{"sym":"F","desc":"96485","unit":"C/mol"}],"notes":"Suy ra hằng số cân bằng: log₁₀(K) = (n · E°_pin) / 0.0592 ở 25°C.","insertText":"ΔG° = -n · F · E°_pin"},{"id":"elec_faraday","title":"Định luật điện phân Faraday","category":"Điện hóa học","expression":"m = (A · I · t) / (n · F)","variables":[{"sym":"m","desc":"Khối lượng chất giải phóng ở điện cực","unit":"g"},{"sym":"A","desc":"Khối lượng mol nguyên tử/chất","unit":"g/mol"},{"sym":"I","desc":"Cường độ dòng điện một chiều","unit":"A"},{"sym":"t","desc":"Thời gian điện phân","unit":"s"},{"sym":"n","desc":"Số electron trao đổi của 1 mol chất","unit":"mol e"}],"notes":"Số mol electron trao đổi: n_e = (I · t) / F.","insertText":"m = (A · I · t) / (n · F)"},{"id":"ana_beer_lambert","title":"Định luật hấp thụ quang Beer-Lambert","category":"Hóa phân tích \u0026 Quang phổ","expression":"A = ε · l · c = -log₁₀(T) = log₁₀(I₀ / I)","variables":[{"sym":"A","desc":"Độ hấp thụ quang (Absorbance)","unit":"không thứ nguyên"},{"sym":"ε","desc":"Hệ số hấp thụ mol","unit":"L/(mol·cm)"},{"sym":"l","desc":"Bề dày cuvet (chiều dài quang trình)","unit":"cm"},{"sym":"c","desc":"Nồng độ mol chất hấp thụ","unit":"mol/L"},{"sym":"T","desc":"Độ truyền qua (I / I₀)","unit":"không thứ nguyên"}],"notes":"Tuyến tính tốt nhất trong khoảng độ hấp thụ A = 0.2 đến 0.8.","insertText":"A = ε · l · c = -log₁₀(T)"},{"id":"ana_dilution","title":"Pha loãng dung dịch \u0026 Chuẩn độ cơ bản","category":"Hóa phân tích \u0026 Quang phổ","expression":"C₁ · V₁ = C₂ · V₂","variables":[{"sym":"C₁, C₂","desc":"Nồng độ dung dịch ban đầu và sau pha loãng","unit":"mol/L (hoặc N)"},{"sym":"V₁, V₂","desc":"Thể tích tương ứng (cùng đơn vị)","unit":"mL hoặc L"}],"notes":"Với phản ứng chuẩn độ aA + bB → sản phẩm: (C_A·V_A)/a = (C_B·V_B)/b.","insertText":"C₁ · V₁ = C₂ · V₂"},{"id":"ana_stats","title":"Độ lệch chuẩn mẫu (s) \u0026 Độ lệch chuẩn tương đối (RSD%)","category":"Hóa phân tích \u0026 Quang phổ","expression":"s = √[ Σ(x_i - x̄)² / (N - 1) ]  ;  RSD% = (s / x̄) × 100%","variables":[{"sym":"x̄","desc":"Giá trị trung bình mẫu","unit":"cùng đơn vị x_i"},{"sym":"N","desc":"Số lần đo lặp lại","unit":"lần"},{"sym":"s","desc":"Độ lệch chuẩn mẫu","unit":"cùng đơn vị x_i"},{"sym":"RSD%","desc":"Độ lệch chuẩn tương đối (đánh giá độ lặp lại)","unit":"%"}],"notes":"Khoảng tin cậy: μ = x̄ ± (t · s) / √N với hệ số Student t.","insertText":"s = √[Σ(x_i - x̄)²/(N-1)] ; RSD% = (s/x̄)×100%"},{"id":"ana_error","title":"Sai số tuyệt đối \u0026 Sai số tương đối","category":"Hóa phân tích \u0026 Quang phổ","expression":"Δx = |x_đo - x_thực|  ;  δ% = (Δx / x_thực) × 100%","variables":[{"sym":"Δx","desc":"Sai số tuyệt đối","unit":"cùng đơn vị x"},{"sym":"δ%","desc":"Sai số tương đối","unit":"%"}],"notes":"Đánh giá độ đúng của phép phân tích định lượng.","insertText":"Δx = |x_đo - x_thực| ; δ% = (Δx / x_thực) × 100%"}];

  const constants = [{"sym":"Nₐ","nameVi":"Hằng số Avogadro","value":"6.022 × 10²³","unit":"mol⁻¹"},{"sym":"R","nameVi":"Hằng số khí lý tưởng","value":"8.3145","unit":"J/(mol·K)"},{"sym":"R","nameVi":"Hằng số khí (hệ atm)","value":"0.08206","unit":"L·atm/(mol·K)"},{"sym":"F","nameVi":"Hằng số Faraday","value":"96485","unit":"C/mol"},{"sym":"h","nameVi":"Hằng số Planck","value":"6.626 × 10⁻³⁴","unit":"J·s"},{"sym":"c","nameVi":"Tốc độ ánh sáng chân không","value":"2.998 × 10⁸","unit":"m/s"},{"sym":"k_B","nameVi":"Hằng số Boltzmann","value":"1.381 × 10⁻²³","unit":"J/K"},{"sym":"K_w","nameVi":"Tích số ion của nước (25°C)","value":"1.0 × 10⁻¹⁴","unit":"mol²/L²"},{"sym":"V_m","nameVi":"Thể tích mol khí ở đkc (25°C, 1 bar)","value":"24.79","unit":"L/mol"},{"sym":"V_m","nameVi":"Thể tích mol khí ở đktc (0°C, 1 atm)","value":"22.414","unit":"L/mol"}];

  const stencils = [{"id":"benzene_ring","nameVi":"Vòng Benzen (vòng tròn)","category":"Vòng hữu cơ","aspectRatio":1},{"id":"benzene_kekule","nameVi":"Vòng Benzen (Kekulé)","category":"Vòng hữu cơ","aspectRatio":1},{"id":"cyclohexane_chair","nameVi":"Xiclohexan (dạng ghế)","category":"Vòng hữu cơ","aspectRatio":1.5},{"id":"cyclohexane_boat","nameVi":"Xiclohexan (dạng thuyền)","category":"Vòng hữu cơ","aspectRatio":1.5},{"id":"cyclopentane","nameVi":"Vòng Xiclopentan","category":"Vòng hữu cơ","aspectRatio":1},{"id":"cyclobutane","nameVi":"Vòng Xiclobutan","category":"Vòng hữu cơ","aspectRatio":1},{"id":"wedge_bond","nameVi":"Liên kết nêm đặc (Wedge)","category":"Liên kết \u0026 Mũi tên","aspectRatio":2},{"id":"dash_bond","nameVi":"Liên kết nêm nét đứt (Dash)","category":"Liên kết \u0026 Mũi tên","aspectRatio":2},{"id":"arrow_reaction","nameVi":"Mũi tên phản ứng","category":"Liên kết \u0026 Mũi tên","aspectRatio":2.5},{"id":"arrow_equilibrium","nameVi":"Mũi tên thuận nghịch","category":"Liên kết \u0026 Mũi tên","aspectRatio":2.5},{"id":"arrow_resonance","nameVi":"Mũi tên cộng hưởng","category":"Liên kết \u0026 Mũi tên","aspectRatio":2.5},{"id":"arrow_curved","nameVi":"Mũi tên cong (cơ chế)","category":"Liên kết \u0026 Mũi tên","aspectRatio":1.6},{"id":"erlenmeyer_flask","nameVi":"Bình tam giác (Erlenmeyer)","category":"Dụng cụ thí nghiệm","aspectRatio":0.8},{"id":"beaker","nameVi":"Cốc thủy tinh (Beaker)","category":"Dụng cụ thí nghiệm","aspectRatio":0.85},{"id":"round_bottom_flask","nameVi":"Bình cầu đáy tròn","category":"Dụng cụ thí nghiệm","aspectRatio":0.78},{"id":"test_tube","nameVi":"Ống nghiệm","category":"Dụng cụ thí nghiệm","aspectRatio":0.35},{"id":"burette","nameVi":"Buret chuẩn độ","category":"Dụng cụ thí nghiệm","aspectRatio":0.32},{"id":"pipette","nameVi":"Pipet bầu","category":"Dụng cụ thí nghiệm","aspectRatio":0.3},{"id":"condenser","nameVi":"Ống sinh hàn (Liebig)","category":"Dụng cụ thí nghiệm","aspectRatio":2.2},{"id":"bunsen_burner","nameVi":"Đèn cồn / Đèn Bunsen","category":"Dụng cụ thí nghiệm","aspectRatio":0.65},{"id":"funnel","nameVi":"Phễu lọc","category":"Dụng cụ thí nghiệm","aspectRatio":0.8}];

  const categoryMeta = {
    alkaliMetal: { labelVi: 'Kim loại kiềm', color: '#E57373' },
    alkalineEarth: { labelVi: 'Kim loại kiềm thổ', color: '#FFB74D' },
    transitionMetal: { labelVi: 'Kim loại chuyển tiếp', color: '#64B5F6' },
    postTransition: { labelVi: 'Kim loại sau chuyển tiếp', color: '#4DB6AC' },
    metalloid: { labelVi: 'Á kim', color: '#81C784' },
    reactiveNonmetal: { labelVi: 'Phi kim hoạt động', color: '#A1887F' },
    halogen: { labelVi: 'Halogen', color: '#BA68C8' },
    nobleGas: { labelVi: 'Khí hiếm', color: '#7986CB' },
    lanthanide: { labelVi: 'Họ Lantan', color: '#F06292' },
    actinide: { labelVi: 'Họ Actini', color: '#FF8A65' },
  };

  const formulaCategories = [
    'Tất cả',
    'Hóa đại cương',
    'Khí lý tưởng & Khí thực',
    'Nhiệt động lực học',
    'Động hóa học',
    'Dung dịch, Cân bằng & pH',
    'Điện hóa học',
    'Hóa phân tích & Quang phổ',
  ];

  const stencilCategories = [
    'Tất cả',
    'Vòng hữu cơ',
    'Liên kết & Mũi tên',
    'Dụng cụ thí nghiệm',
  ];

  const chemSymbols = [
    '₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉',
    '⁺', '⁻', '²⁺', '³⁺', '²⁻',
    '→', '⇌', '↔', 'Δ', '°', '↑', '↓', '·',
    'λ⁰', 'μ⁰', 'α', 'β', 'γ', 'π', 'Σ',
  ];

  const elementsBySymbol = Object.create(null);
  const elementsByNumber = Object.create(null);
  for (let i = 0; i < elements.length; i++) {
    const el = elements[i];
    elementsBySymbol[el.symbol] = el;
    elementsByNumber[el.z] = el;
  }

  function isDigitCode(c) { return c >= 48 && c <= 57; }
  function isUpperCode(c) { return c >= 65 && c <= 90; }
  function isLowerCode(c) { return c >= 97 && c <= 122; }

  const matchingClose = { '(': ')', '[': ']', '{': '}' };

  function parseSegment(segment, startPos) {
    let pos = startPos;

    function readOptionalNumber() {
      if (pos >= segment.length || !isDigitCode(segment.charCodeAt(pos))) {
        return 1;
      }
      const s = pos;
      while (pos < segment.length && isDigitCode(segment.charCodeAt(pos))) {
        pos++;
      }
      const val = parseInt(segment.slice(s, pos), 10);
      if (!(val > 0)) {
        throw new Error('Chỉ số nguyên tử phải lớn hơn 0.');
      }
      return val;
    }

    function parseGroup(expectedClose) {
      const counts = Object.create(null);
      while (pos < segment.length) {
        const ch = segment[pos];
        if (ch === ')' || ch === ']' || ch === '}') {
          if (expectedClose === null) {
            throw new Error('Dư dấu đóng ngoặc "' + ch + '".');
          }
          if (ch !== expectedClose) {
            throw new Error('Ngoặc không khớp: cần "' + expectedClose + '" nhưng gặp "' + ch + '".');
          }
          pos++;
          return counts;
        }
        if (matchingClose[ch]) {
          const closeChar = matchingClose[ch];
          pos++;
          const inner = parseGroup(closeChar);
          const keys = Object.keys(inner);
          if (keys.length === 0) {
            throw new Error('Nhóm ngoặc "' + ch + closeChar + '" rỗng.');
          }
          const mult = readOptionalNumber();
          for (let k = 0; k < keys.length; k++) {
            const sym = keys[k];
            counts[sym] = (counts[sym] || 0) + inner[sym] * mult;
          }
          continue;
        }
        const code = ch.charCodeAt(0);
        if (isUpperCode(code)) {
          const s = pos;
          pos++;
          while (pos < segment.length && isLowerCode(segment.charCodeAt(pos))) {
            pos++;
          }
          const sym = segment.slice(s, pos);
          if (!elementsBySymbol[sym]) {
            throw new Error('Ký hiệu nguyên tố không hợp lệ: "' + sym + '".');
          }
          const mult = readOptionalNumber();
          counts[sym] = (counts[sym] || 0) + mult;
          continue;
        }
        if (isLowerCode(code)) {
          throw new Error('Ký hiệu nguyên tố phải viết hoa chữ cái đầu (VD: H2O, NaCl) — lỗi tại "' + ch + '".');
        }
        throw new Error('Ký tự không hợp lệ "' + ch + '" trong công thức.');
      }
      if (expectedClose !== null) {
        throw new Error('Thiếu dấu đóng ngoặc "' + expectedClose + '".');
      }
      return counts;
    }

    const res = parseGroup(null);
    if (pos < segment.length) {
      throw new Error('Ký tự không hợp lệ "' + segment[pos] + '" tại vị trí ' + (pos + 1) + '.');
    }
    return res;
  }

  function parseFormula(rawFormula) {
    const trimmed = String(rawFormula == null ? '' : rawFormula).trim();
    if (!trimmed) {
      throw new Error('Vui lòng nhập công thức hóa học.');
    }
    const normalized = trimmed.replace(/\s+/g, '');
    const segments = normalized.split(/[.·•*]/);
    const totalCounts = Object.create(null);

    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];
      if (!seg) {
        throw new Error('Cú pháp hydrat không hợp lệ (có dấu chấm thừa hoặc thiếu chất).');
      }
      let idx = 0;
      let coeff = 1;
      if (isDigitCode(seg.charCodeAt(idx))) {
        const s = idx;
        while (idx < seg.length && isDigitCode(seg.charCodeAt(idx))) {
          idx++;
        }
        coeff = parseInt(seg.slice(s, idx), 10);
        if (!(coeff > 0)) {
          throw new Error('Hệ số phải lớn hơn 0.');
        }
        if (idx >= seg.length) {
          throw new Error('Thiếu công thức chất sau hệ số.');
        }
      }
      const segCounts = parseSegment(seg, idx);
      const keys = Object.keys(segCounts);
      if (keys.length === 0) {
        throw new Error('Công thức không chứa nguyên tố nào.');
      }
      for (let k = 0; k < keys.length; k++) {
        const sym = keys[k];
        totalCounts[sym] = (totalCounts[sym] || 0) + segCounts[sym] * coeff;
      }
    }
    return totalCounts;
  }

  function calculateMolarMass(formulaStr) {
    const trimmed = String(formulaStr == null ? '' : formulaStr).trim();
    const counts = parseFormula(trimmed);
    const keys = Object.keys(counts);
    let totalMass = 0;
    const rawEntries = [];

    for (let i = 0; i < keys.length; i++) {
      const sym = keys[i];
      const el = elementsBySymbol[sym];
      if (!el) {
        throw new Error('Không tìm thấy nguyên tố "' + sym + '".');
      }
      const count = counts[sym];
      const subtotal = el.mass * count;
      totalMass += subtotal;
      rawEntries.push({ el: el, count: count, subtotal: subtotal });
    }

    const breakdown = rawEntries.map(function (item) {
      const pct = totalMass > 0 ? (item.subtotal / totalMass) * 100 : 0;
      return {
        symbol: item.el.symbol,
        nameVi: item.el.nameVi,
        atomicMass: item.el.mass,
        count: item.count,
        mass: item.subtotal,
        percent: pct,
      };
    });

    const parts = breakdown
      .map(function (b) { return b.symbol + ': ' + b.count + ' (' + b.percent.toFixed(1) + '%)'; })
      .join(', ');

    return {
      formula: trimmed,
      totalMass: totalMass,
      breakdown: breakdown,
      formattedSummary: 'M(' + trimmed + ') = ' + totalMass.toFixed(2) + ' g/mol  [' + parts + ']',
    };
  }

  // ==================== 21 VECTOR STENCILS (Canvas 2D) ====================
  function drawStencil(ctx, stencilId, x, y, w, h, color, strokeWidth) {
    if (!ctx || w <= 0 || h <= 0) return;
    const sw = strokeWidth || 2;
    const strokeColor = color || '#1E293B';

    ctx.save();
    ctx.strokeStyle = strokeColor;
    ctx.fillStyle = strokeColor;
    ctx.lineWidth = sw;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    const pad = sw * 1.2 + Math.min(w, h) * 0.06;
    const rx = x + pad;
    const ry = y + pad;
    const rw = Math.max(1, w - pad * 2);
    const rh = Math.max(1, h - pad * 2);
    const cx = rx + rw / 2;
    const cy = ry + rh / 2;

    function pt(fx, fy) {
      return [rx + rw * fx, ry + rh * fy];
    }

    function line(x1, y1, x2, y2) {
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }

    function polyVerts(sides, startAngle) {
      const r = Math.min(rw, rh) * 0.48;
      const out = [];
      for (let i = 0; i < sides; i++) {
        const a = startAngle + (2 * Math.PI * i) / sides;
        out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
      }
      return out;
    }

    function drawPoly(sides, startAngle) {
      const v = polyVerts(sides, startAngle);
      ctx.beginPath();
      ctx.moveTo(v[0][0], v[0][1]);
      for (let i = 1; i < v.length; i++) ctx.lineTo(v[i][0], v[i][1]);
      ctx.closePath();
      ctx.stroke();
      return v;
    }

    function lerp(a, b, t) {
      return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    }

    switch (stencilId) {
      case 'benzene_ring': {
        drawPoly(6, -Math.PI / 2);
        const r = Math.min(rw, rh) * 0.48;
        ctx.beginPath();
        ctx.arc(cx, cy, r * 0.62, 0, Math.PI * 2);
        ctx.stroke();
        break;
      }
      case 'benzene_kekule': {
        const v = drawPoly(6, -Math.PI / 2);
        const center = [cx, cy];
        [0, 2, 4].forEach(function (idx) {
          const a = v[idx];
          const b = v[(idx + 1) % 6];
          const ia = lerp(a, center, 0.2);
          const ib = lerp(b, center, 0.2);
          const p1 = lerp(ia, ib, 0.1);
          const p2 = lerp(ia, ib, 0.9);
          line(p1[0], p1[1], p2[0], p2[1]);
        });
        break;
      }
      case 'cyclohexane_chair': {
        const pts = [pt(0.05, 0.62), pt(0.32, 0.26), pt(0.68, 0.42), pt(0.95, 0.32), pt(0.68, 0.74), pt(0.32, 0.58)];
        ctx.beginPath();
        ctx.moveTo(pts[0][0], pts[0][1]);
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
        ctx.closePath();
        ctx.stroke();
        break;
      }
      case 'cyclohexane_boat': {
        const pts = [pt(0.06, 0.28), pt(0.30, 0.74), pt(0.70, 0.74), pt(0.94, 0.28), pt(0.68, 0.50), pt(0.32, 0.50)];
        ctx.beginPath();
        ctx.moveTo(pts[0][0], pts[0][1]);
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
        ctx.closePath();
        ctx.stroke();
        break;
      }
      case 'cyclopentane':
        drawPoly(5, -Math.PI / 2);
        break;
      case 'cyclobutane':
        drawPoly(4, -Math.PI / 4);
        break;
      case 'wedge_bond': {
        const halfH = rh * 0.24;
        ctx.beginPath();
        ctx.moveTo(rx, cy);
        ctx.lineTo(rx + rw, cy - halfH);
        ctx.lineTo(rx + rw, cy + halfH);
        ctx.closePath();
        ctx.fill();
        break;
      }
      case 'dash_bond': {
        const maxHalfH = rh * 0.24;
        for (let i = 0; i < 6; i++) {
          const t = (i + 0.5) / 6;
          const dx = rx + rw * t;
          const hh = maxHalfH * t;
          line(dx, cy - hh, dx, cy + hh);
        }
        break;
      }
      case 'arrow_reaction': {
        const hl = Math.min(rw * 0.2, rh * 0.35);
        line(rx, cy, rx + rw, cy);
        line(rx + rw - hl, cy - hl * 0.65, rx + rw, cy);
        line(rx + rw - hl, cy + hl * 0.65, rx + rw, cy);
        break;
      }
      case 'arrow_equilibrium': {
        const gap = Math.max(sw * 1.8, rh * 0.14);
        const hl = Math.min(rw * 0.18, rh * 0.32);
        const topY = cy - gap;
        line(rx, topY, rx + rw, topY);
        line(rx + rw - hl, topY - hl * 0.6, rx + rw, topY);
        const botY = cy + gap;
        line(rx + rw, botY, rx, botY);
        line(rx + hl, botY + hl * 0.6, rx, botY);
        break;
      }
      case 'arrow_resonance': {
        const hl = Math.min(rw * 0.18, rh * 0.34);
        line(rx, cy, rx + rw, cy);
        line(rx + rw - hl, cy - hl * 0.65, rx + rw, cy);
        line(rx + rw - hl, cy + hl * 0.65, rx + rw, cy);
        line(rx + hl, cy - hl * 0.65, rx, cy);
        line(rx + hl, cy + hl * 0.65, rx, cy);
        break;
      }
      case 'arrow_curved': {
        const sx = rx + rw * 0.08, sy = ry + rh * 0.78;
        const kx = cx, ky = ry - rh * 0.05;
        const ex = rx + rw * 0.92, ey = ry + rh * 0.78;
        ctx.beginPath();
        ctx.moveTo(sx, sy);
        ctx.quadraticCurveTo(kx, ky, ex, ey);
        ctx.stroke();
        const ang = Math.atan2(ey - ky, ex - kx);
        const hl = Math.min(rw, rh) * 0.22;
        line(ex, ey, ex - hl * Math.cos(ang - 0.55), ey - hl * Math.sin(ang - 0.55));
        line(ex, ey, ex - hl * Math.cos(ang + 0.55), ey - hl * Math.sin(ang + 0.55));
        break;
      }
      case 'erlenmeyer_flask': {
        const p1 = pt(0.34, 0.05), p2 = pt(0.66, 0.05);
        line(p1[0], p1[1], p2[0], p2[1]);
        ctx.beginPath();
        ctx.moveTo(pt(0.38, 0.05)[0], pt(0.38, 0.05)[1]);
        ctx.lineTo(pt(0.38, 0.34)[0], pt(0.38, 0.34)[1]);
        ctx.lineTo(pt(0.10, 0.88)[0], pt(0.10, 0.88)[1]);
        ctx.quadraticCurveTo(pt(0.08, 0.96)[0], pt(0.08, 0.96)[1], pt(0.18, 0.96)[0], pt(0.18, 0.96)[1]);
        ctx.lineTo(pt(0.82, 0.96)[0], pt(0.82, 0.96)[1]);
        ctx.quadraticCurveTo(pt(0.92, 0.96)[0], pt(0.92, 0.96)[1], pt(0.90, 0.88)[0], pt(0.90, 0.88)[1]);
        ctx.lineTo(pt(0.62, 0.34)[0], pt(0.62, 0.34)[1]);
        ctx.lineTo(pt(0.62, 0.05)[0], pt(0.62, 0.05)[1]);
        ctx.stroke();
        ctx.globalAlpha = 0.55;
        ctx.lineWidth = Math.max(1, sw * 0.75);
        line(pt(0.24, 0.68)[0], pt(0.24, 0.68)[1], pt(0.76, 0.68)[0], pt(0.76, 0.68)[1]);
        break;
      }
      case 'beaker': {
        ctx.beginPath();
        ctx.moveTo(pt(0.12, 0.08)[0], pt(0.12, 0.08)[1]);
        ctx.lineTo(pt(0.20, 0.16)[0], pt(0.20, 0.16)[1]);
        ctx.lineTo(pt(0.20, 0.88)[0], pt(0.20, 0.88)[1]);
        ctx.quadraticCurveTo(pt(0.20, 0.95)[0], pt(0.20, 0.95)[1], pt(0.28, 0.95)[0], pt(0.28, 0.95)[1]);
        ctx.lineTo(pt(0.76, 0.95)[0], pt(0.76, 0.95)[1]);
        ctx.quadraticCurveTo(pt(0.84, 0.95)[0], pt(0.84, 0.95)[1], pt(0.84, 0.88)[0], pt(0.84, 0.88)[1]);
        ctx.lineTo(pt(0.84, 0.10)[0], pt(0.84, 0.10)[1]);
        ctx.lineTo(pt(0.12, 0.08)[0], pt(0.12, 0.08)[1]);
        ctx.stroke();
        ctx.globalAlpha = 0.7;
        ctx.lineWidth = Math.max(1, sw * 0.75);
        [0.34, 0.50, 0.66, 0.80].forEach(function (fy) {
          line(pt(0.64, fy)[0], pt(0.64, fy)[1], pt(0.78, fy)[0], pt(0.78, fy)[1]);
        });
        break;
      }
      case 'round_bottom_flask': {
        const radius = Math.min(rw * 0.42, rh * 0.32);
        const ccy = ry + rh - radius - rh * 0.03;
        const neckHalfW = radius * 0.30;
        const neckTop = ry + rh * 0.05;
        const neckJoinY = ccy - Math.sqrt(Math.max(0, radius * radius - neckHalfW * neckHalfW));
        line(cx - neckHalfW * 1.25, neckTop, cx + neckHalfW * 1.25, neckTop);
        line(cx - neckHalfW, neckTop, cx - neckHalfW, neckJoinY);
        line(cx + neckHalfW, neckTop, cx + neckHalfW, neckJoinY);
        const openAngle = Math.asin(Math.max(0, Math.min(1, neckHalfW / radius)));
        ctx.beginPath();
        ctx.arc(cx, ccy, radius, -Math.PI / 2 + openAngle, (3 * Math.PI) / 2 - openAngle, false);
        ctx.stroke();
        break;
      }
      case 'test_tube': {
        const halfW = Math.min(rw * 0.34, rh * 0.16);
        const topY = ry + rh * 0.06;
        const arcY = ry + rh - halfW - rh * 0.04;
        line(cx - halfW * 1.3, topY, cx + halfW * 1.3, topY);
        ctx.beginPath();
        ctx.moveTo(cx - halfW, topY);
        ctx.lineTo(cx - halfW, arcY);
        ctx.arc(cx, arcY, halfW, Math.PI, 0, true);
        ctx.lineTo(cx + halfW, topY);
        ctx.stroke();
        ctx.lineWidth = Math.max(1, sw * 0.75);
        const ly = ry + rh * 0.56;
        line(cx - halfW * 0.85, ly, cx + halfW * 0.85, ly);
        break;
      }
      case 'burette': {
        const halfW = Math.min(rw * 0.24, rh * 0.09);
        const topY = ry + rh * 0.04;
        const taperY = ry + rh * 0.72;
        const stopY = ry + rh * 0.82;
        const tipY = ry + rh * 0.97;
        line(cx - halfW * 1.35, topY, cx + halfW * 1.35, topY);
        ctx.beginPath();
        ctx.moveTo(cx - halfW, topY);
        ctx.lineTo(cx - halfW, taperY);
        ctx.lineTo(cx - halfW * 0.32, stopY);
        ctx.lineTo(cx - halfW * 0.22, tipY);
        ctx.moveTo(cx + halfW, topY);
        ctx.lineTo(cx + halfW, taperY);
        ctx.lineTo(cx + halfW * 0.32, stopY);
        ctx.lineTo(cx + halfW * 0.22, tipY);
        ctx.stroke();
        line(cx - halfW * 1.8, stopY, cx + halfW * 1.8, stopY);
        ctx.beginPath();
        ctx.arc(cx + halfW * 1.8, stopY, halfW * 0.45, 0, Math.PI * 2);
        ctx.stroke();
        ctx.globalAlpha = 0.75;
        ctx.lineWidth = Math.max(1, sw * 0.7);
        for (let i = 1; i <= 6; i++) {
          const ty = topY + ((taperY - topY) * i) / 7;
          const len = i % 2 === 0 ? halfW * 0.9 : halfW * 0.55;
          line(cx + halfW - len, ty, cx + halfW, ty);
        }
        break;
      }
      case 'pipette': {
        const stemW = Math.min(rw * 0.14, rh * 0.045);
        const bulbW = Math.min(rw * 0.36, rh * 0.13);
        const topY = ry + rh * 0.04;
        const bTop = ry + rh * 0.32;
        const bBot = ry + rh * 0.64;
        const tipY = ry + rh * 0.96;
        line(cx - stemW, topY, cx - stemW, bTop);
        line(cx + stemW, topY, cx + stemW, bTop);
        line(cx - stemW * 1.7, ry + rh * 0.18, cx + stemW * 1.7, ry + rh * 0.18);
        ctx.beginPath();
        ctx.moveTo(cx - stemW, bTop);
        ctx.quadraticCurveTo(cx - bulbW * 1.35, (bTop + bBot) / 2, cx - stemW, bBot);
        ctx.moveTo(cx + stemW, bTop);
        ctx.quadraticCurveTo(cx + bulbW * 1.35, (bTop + bBot) / 2, cx + stemW, bBot);
        ctx.stroke();
        line(cx - stemW, bBot, cx - stemW * 0.35, tipY);
        line(cx + stemW, bBot, cx + stemW * 0.35, tipY);
        break;
      }
      case 'condenser': {
        const innerH = rh * 0.11;
        const jacketH = rh * 0.28;
        const jL = rx + rw * 0.18;
        const jR = rx + rw * 0.82;
        line(rx, cy - innerH, rx + rw, cy - innerH);
        line(rx, cy + innerH, rx + rw, cy + innerH);
        ctx.strokeRect(jL, cy - jacketH, jR - jL, jacketH * 2);
        const noz = rh * 0.22;
        line(jL + rw * 0.08, cy - jacketH, jL + rw * 0.08, cy - jacketH - noz);
        line(jR - rw * 0.08, cy + jacketH, jR - rw * 0.08, cy + jacketH + noz);
        break;
      }
      case 'bunsen_burner': {
        const baseY = ry + rh * 0.94;
        const tubeW = rw * 0.11;
        const tubeTop = ry + rh * 0.38;
        const baseTop = ry + rh * 0.82;
        ctx.beginPath();
        ctx.moveTo(cx, ry + rh * 0.05);
        ctx.quadraticCurveTo(cx + tubeW * 2.0, ry + rh * 0.24, cx, tubeTop - rh * 0.03);
        ctx.quadraticCurveTo(cx - tubeW * 2.0, ry + rh * 0.24, cx, ry + rh * 0.05);
        ctx.stroke();
        ctx.strokeRect(cx - tubeW, tubeTop, tubeW * 2, baseTop - tubeTop);
        line(cx + tubeW, baseTop - rh * 0.08, rx + rw * 0.90, baseTop - rh * 0.08);
        ctx.beginPath();
        ctx.moveTo(rx + rw * 0.16, baseY);
        ctx.lineTo(rx + rw * 0.26, baseTop);
        ctx.lineTo(rx + rw * 0.74, baseTop);
        ctx.lineTo(rx + rw * 0.84, baseY);
        ctx.closePath();
        ctx.stroke();
        break;
      }
      case 'funnel': {
        line(pt(0.08, 0.10)[0], pt(0.08, 0.10)[1], pt(0.92, 0.10)[0], pt(0.92, 0.10)[1]);
        ctx.beginPath();
        ctx.moveTo(pt(0.08, 0.10)[0], pt(0.08, 0.10)[1]);
        ctx.lineTo(pt(0.43, 0.56)[0], pt(0.43, 0.56)[1]);
        ctx.lineTo(pt(0.43, 0.94)[0], pt(0.43, 0.94)[1]);
        ctx.lineTo(pt(0.57, 0.86)[0], pt(0.57, 0.86)[1]);
        ctx.lineTo(pt(0.57, 0.56)[0], pt(0.57, 0.56)[1]);
        ctx.lineTo(pt(0.92, 0.10)[0], pt(0.92, 0.10)[1]);
        ctx.stroke();
        break;
      }
      default:
        drawPoly(6, -Math.PI / 2);
        break;
    }

    ctx.restore();
  }

  // ==================== CHEMICAL EQUATION BALANCER ====================
  const SUBSCRIPT_DIGITS = ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉'];

  function formatFormulaSubscripts(formula) {
    const segs = String(formula).trim().split(/[.·•*]/);
    return segs.map(function (seg) {
      let i = 0;
      while (i < seg.length && isDigitCode(seg.charCodeAt(i))) i++;
      const lead = seg.slice(0, i);
      const rest = seg.slice(i).replace(/[0-9]/g, function (d) {
        return SUBSCRIPT_DIGITS[d.charCodeAt(0) - 48];
      });
      return lead + rest;
    }).join('·');
  }

  function bgcd(a, b) {
    let x = a < 0n ? -a : a;
    let y = b < 0n ? -b : b;
    while (y !== 0n) {
      const t = x % y;
      x = y;
      y = t;
    }
    return x === 0n ? 1n : x;
  }

  function blcm(a, b) {
    if (a === 0n || b === 0n) return 0n;
    const x = a < 0n ? -a : a;
    const y = b < 0n ? -b : b;
    return (x / bgcd(x, y)) * y;
  }

  function frac(n, d) {
    let num = BigInt(n);
    let den = BigInt(d == null ? 1 : d);
    if (den < 0n) { num = -num; den = -den; }
    if (num === 0n) return { n: 0n, d: 1n };
    const g = bgcd(num, den);
    return { n: num / g, d: den / g };
  }

  function fAdd(a, b) { return frac(a.n * b.d + b.n * a.d, a.d * b.d); }
  function fSub(a, b) { return frac(a.n * b.d - b.n * a.d, a.d * b.d); }
  function fMul(a, b) { return frac(a.n * b.n, a.d * b.d); }
  function fDiv(a, b) { return frac(a.n * b.d, a.d * b.n); }

  function stripLeadingCoeff(token) {
    const t = token.trim();
    let i = 0;
    while (i < t.length && isDigitCode(t.charCodeAt(i))) i++;
    return i < t.length ? t.slice(i).trim() : t;
  }

  function balanceEquation(input) {
    const raw = String(input == null ? '' : input).trim();
    if (!raw) {
      throw new Error('Vui lòng nhập phương trình hóa học (VD: Fe + O2 -> Fe3O4).');
    }

    // Normalize Unicode subscripts back to ASCII digits for parsing
    const asciiInput = raw.replace(/[₀₁₂₃₄₅₆₇₈₉]/g, function (ch) {
      return String(SUBSCRIPT_DIGITS.indexOf(ch));
    });

    const arrowMatch = asciiInput.match(/<=>|<->|⇌|↔|->|=>|→|=/);
    if (!arrowMatch) {
      throw new Error('Thiếu dấu mũi tên phản ứng (dùng ->, =, → hoặc ⇌).');
    }

    const rawArrow = arrowMatch[0];
    const displayArrow = (rawArrow === '<=>' || rawArrow === '<->' || rawArrow === '⇌') ? '⇌' : '→';
    const sides = asciiInput.split(rawArrow);
    if (sides.length !== 2 || !sides[0].trim() || !sides[1].trim()) {
      throw new Error('Phương trình phải có đúng 2 vế (chất tham gia và sản phẩm).');
    }

    const reactantTokens = sides[0].split('+').map(stripLeadingCoeff).filter(Boolean);
    const productTokens = sides[1].split('+').map(stripLeadingCoeff).filter(Boolean);
    if (reactantTokens.length === 0 || productTokens.length === 0) {
      throw new Error('Thiếu công thức chất ở vế trái hoặc vế phải.');
    }

    const allTokens = reactantTokens.concat(productTokens);
    const parsedList = allTokens.map(function (tok) { return parseFormula(tok); });

    const elemSet = Object.create(null);
    const elems = [];
    for (let i = 0; i < parsedList.length; i++) {
      const ks = Object.keys(parsedList[i]);
      for (let j = 0; j < ks.length; j++) {
        if (!elemSet[ks[j]]) {
          elemSet[ks[j]] = true;
          elems.push(ks[j]);
        }
      }
    }

    const numRows = elems.length;
    const numCols = allTokens.length;
    const mat = [];
    for (let r = 0; r < numRows; r++) {
      const row = [];
      const elSym = elems[r];
      for (let c = 0; c < numCols; c++) {
        const cnt = parsedList[c][elSym] || 0;
        const sign = c < reactantTokens.length ? 1 : -1;
        row.push(frac(sign * cnt, 1));
      }
      mat.push(row);
    }

    // Exact Rational Gauss-Jordan Elimination (RREF)
    const pivotCols = [];
    let pivotRow = 0;
    for (let col = 0; col < numCols && pivotRow < numRows; col++) {
      let found = -1;
      for (let r = pivotRow; r < numRows; r++) {
        if (mat[r][col].n !== 0n) { found = r; break; }
      }
      if (found === -1) continue;

      if (found !== pivotRow) {
        const tmp = mat[pivotRow];
        mat[pivotRow] = mat[found];
        mat[found] = tmp;
      }

      const pivVal = mat[pivotRow][col];
      for (let c = col; c < numCols; c++) {
        mat[pivotRow][c] = fDiv(mat[pivotRow][c], pivVal);
      }

      for (let r = 0; r < numRows; r++) {
        if (r === pivotRow || mat[r][col].n === 0n) continue;
        const factor = mat[r][col];
        for (let c = col; c < numCols; c++) {
          mat[r][c] = fSub(mat[r][c], fMul(factor, mat[pivotRow][c]));
        }
      }

      pivotCols.push(col);
      pivotRow++;
    }

    const isPivot = Object.create(null);
    for (let i = 0; i < pivotCols.length; i++) isPivot[pivotCols[i]] = true;
    const freeCols = [];
    for (let c = 0; c < numCols; c++) {
      if (!isPivot[c]) freeCols.push(c);
    }

    if (freeCols.length === 0) {
      throw new Error('Không thể cân bằng phương trình — kiểm tra lại nguyên tố hai vế.');
    }

    // Solve nullspace by setting free variable(s) = 1
    const sol = new Array(numCols);
    for (let c = 0; c < numCols; c++) sol[c] = frac(0, 1);
    for (let i = 0; i < freeCols.length; i++) sol[freeCols[i]] = frac(1, 1);

    for (let r = 0; r < pivotCols.length; r++) {
      const pCol = pivotCols[r];
      let sum = frac(0, 1);
      for (let i = 0; i < freeCols.length; i++) {
        const fCol = freeCols[i];
        sum = fAdd(sum, mat[r][fCol]);
      }
      sol[pCol] = frac(-sum.n, sum.d);
    }

    let commonDen = 1n;
    for (let c = 0; c < numCols; c++) {
      commonDen = blcm(commonDen, sol[c].d);
    }
    const intCoeffs = sol.map(function (v) { return (v.n * commonDen) / v.d; });

    if (intCoeffs.every(function (v) { return v < 0n; })) {
      for (let c = 0; c < numCols; c++) intCoeffs[c] = -intCoeffs[c];
    }

    if (intCoeffs.some(function (v) { return v <= 0n; })) {
      throw new Error('Không tìm được bộ hệ số nguyên dương — vui lòng kiểm tra lại các chất tham gia và sản phẩm.');
    }

    let commonGcd = intCoeffs[0];
    for (let c = 1; c < numCols; c++) commonGcd = bgcd(commonGcd, intCoeffs[c]);
    const coeffs = intCoeffs.map(function (v) { return Number(v / commonGcd); });

    const reactants = reactantTokens.map(function (f, i) {
      const c = coeffs[i];
      const fmt = (c > 1 ? String(c) : '') + formatFormulaSubscripts(f);
      return { formula: f, coeff: c, formatted: fmt };
    });
    const products = productTokens.map(function (f, i) {
      const c = coeffs[reactantTokens.length + i];
      const fmt = (c > 1 ? String(c) : '') + formatFormulaSubscripts(f);
      return { formula: f, coeff: c, formatted: fmt };
    });

    const balanced =
      reactants.map(function (r) { return r.formatted; }).join(' + ') +
      ' ' + displayArrow + ' ' +
      products.map(function (p) { return p.formatted; }).join(' + ');

    const plain =
      reactants.map(function (r) { return (r.coeff > 1 ? String(r.coeff) : '') + r.formula; }).join(' + ') +
      ' -> ' +
      products.map(function (p) { return (p.coeff > 1 ? String(p.coeff) : '') + p.formula; }).join(' + ');

    return {
      balanced: balanced,
      plain: plain,
      arrow: displayArrow,
      coefficients: coeffs,
      reactants: reactants,
      products: products,
    };
  }

  window.CHEM_DATA = {
    elements: elements,
    categoryMeta: categoryMeta,
    findElementBySymbol: function (sym) { return elementsBySymbol[sym] || null; },
    findElementByNumber: function (z) { return elementsByNumber[z] || null; },
    formulaCategories: formulaCategories,
    formulas: formulas,
    constants: constants,
    stencilCategories: stencilCategories,
    stencils: stencils,
    chemSymbols: chemSymbols,
    parseFormula: parseFormula,
    calculateMolarMass: calculateMolarMass,
    formatFormulaSubscripts: formatFormulaSubscripts,
    balanceEquation: balanceEquation,
    drawStencil: drawStencil,
  };
})();
