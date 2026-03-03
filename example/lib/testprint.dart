import 'package:drago_blue_printer/drago_blue_printer.dart';

class TestPrint {
  final DragoBluePrinter bluetooth = DragoBluePrinter.instance;

  // ── Format constants (32-char width for 58mm printers) ──────────────────
  static const _col2 = '%-16s %16s %n';
  static const _col3 = '%-14s %6s %10s %n';
  static const _col4 = '%-9s %6s %5s %8s %n';
  static const _sep = '================================';
  static const _dot = '................................';

  /// Batch print — full A4-height receipt in a single method-channel call.
  Future<void> sampleBatch() async {
    final isConnected = await bluetooth.isConnected ?? false;
    if (!isConnected) return;

    await bluetooth.printBatch([
      // ════════════════════════════════════════════════════════════════════
      //  STORE HEADER
      // ════════════════════════════════════════════════════════════════════
      PrintCommand.newLine(),
      PrintCommand.newLine(),
      PrintCommand.custom('DRAGO CAFE', 3, 1),
      PrintCommand.custom('& RESTAURANT', 2, 1),
      PrintCommand.newLine(),
      PrintCommand.custom('123 Flutter Avenue', 0, 1),
      PrintCommand.custom('Dart City, DC 10101', 0, 1),
      PrintCommand.custom('Tel: (555) 123-4567', 0, 1),
      PrintCommand.custom('www.dragocafe.dev', 0, 1),
      PrintCommand.newLine(),
      PrintCommand.custom(_sep, 0, 1),
      PrintCommand.custom('TAX INVOICE', 2, 1),
      PrintCommand.custom(_sep, 0, 1),
      PrintCommand.newLine(),

      // ── Order info ──────────────────────────────────────────────────────
      PrintCommand.leftRight('Order #:', '00042857', 0, format: _col2),
      PrintCommand.leftRight('Date:', '03/03/2026', 0, format: _col2),
      PrintCommand.leftRight('Time:', '14:32:08', 0, format: _col2),
      PrintCommand.leftRight('Table:', 'T-12', 0, format: _col2),
      PrintCommand.leftRight('Server:', 'Alex M.', 0, format: _col2),
      PrintCommand.leftRight('Guests:', '4', 0, format: _col2),
      PrintCommand.newLine(),
      PrintCommand.custom(_sep, 0, 1),

      // ════════════════════════════════════════════════════════════════════
      //  BEVERAGES
      // ════════════════════════════════════════════════════════════════════
      PrintCommand.custom('BEVERAGES', 1, 0),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Item', 'Qty', 'Amount', 1, format: _col3),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Espresso', '2', '\$7.00', 0, format: _col3),
      PrintCommand.threeColumn('Cappuccino', '1', '\$4.50', 0, format: _col3),
      PrintCommand.threeColumn('Caffe Latte', '3', '\$13.50', 0,
          format: _col3),
      PrintCommand.threeColumn('Iced Americano', '2', '\$9.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Green Tea', '1', '\$3.00', 0, format: _col3),
      PrintCommand.threeColumn('Fresh OJ', '2', '\$8.00', 0, format: _col3),
      PrintCommand.threeColumn('Sparkling Wtr', '4', '\$12.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Hot Chocolate', '2', '\$7.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Chai Latte', '1', '\$4.50', 0, format: _col3),
      PrintCommand.threeColumn('Mint Lemonade', '2', '\$6.00', 0,
          format: _col3),
      PrintCommand.newLine(),

      // ════════════════════════════════════════════════════════════════════
      //  STARTERS
      // ════════════════════════════════════════════════════════════════════
      PrintCommand.custom('STARTERS', 1, 0),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Item', 'Qty', 'Amount', 1, format: _col3),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Bruschetta', '2', '\$12.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Caesar Salad', '1', '\$9.50', 0,
          format: _col3),
      PrintCommand.threeColumn('Soup of Day', '2', '\$11.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Garlic Bread', '1', '\$5.50', 0,
          format: _col3),
      PrintCommand.threeColumn('Spring Rolls', '2', '\$8.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Hummus Plate', '1', '\$7.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Calamari', '1', '\$10.00', 0, format: _col3),
      PrintCommand.threeColumn('Caprese Salad', '1', '\$8.50', 0,
          format: _col3),
      PrintCommand.newLine(),

      // ════════════════════════════════════════════════════════════════════
      //  MAIN COURSES
      // ════════════════════════════════════════════════════════════════════
      PrintCommand.custom('MAIN COURSES', 1, 0),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Item', 'Qty', 'Amount', 1, format: _col3),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Grilled Salmon', '2', '\$32.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Ribeye Steak', '1', '\$28.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Chicken Parm', '1', '\$18.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Pasta Alfredo', '2', '\$24.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Margherita Pz', '1', '\$14.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Veg Risotto', '1', '\$16.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Fish & Chips', '1', '\$15.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Lamb Chops', '1', '\$26.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Beef Burger', '2', '\$22.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Shrimp Scampi', '1', '\$19.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Duck Confit', '1', '\$24.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Tofu Stir Fry', '1', '\$13.00', 0,
          format: _col3),
      PrintCommand.newLine(),

      // ════════════════════════════════════════════════════════════════════
      //  SIDES
      // ════════════════════════════════════════════════════════════════════
      PrintCommand.custom('SIDES', 1, 0),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('Item', 'Qty', 'Amount', 1, format: _col3),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.threeColumn('French Fries', '3', '\$13.50', 0,
          format: _col3),
      PrintCommand.threeColumn('Mashed Potato', '2', '\$7.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Coleslaw', '2', '\$5.00', 0, format: _col3),
      PrintCommand.threeColumn('Grilled Vegs', '2', '\$9.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Rice Pilaf', '1', '\$4.00', 0, format: _col3),
      PrintCommand.threeColumn('Sweet Potato', '2', '\$7.00', 0,
          format: _col3),
      PrintCommand.threeColumn('Garden Salad', '1', '\$4.50', 0,
          format: _col3),
      PrintCommand.threeColumn('Onion Rings', '2', '\$6.00', 0,
          format: _col3),
      PrintCommand.newLine(),
 

      // ── Loyalty program ─────────────────────────────────────────────────
      PrintCommand.custom('LOYALTY REWARDS', 1, 1),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.leftRight('Member ID:', 'DRG-0042857', 0, format: _col2),
      PrintCommand.leftRight('Points Earned:', '+613', 0, format: _col2),
      PrintCommand.leftRight('Bonus Points:', '+100', 0, format: _col2),
      PrintCommand.leftRight('Total Points:', '9,253', 0, format: _col2),
      PrintCommand.leftRight('Tier:', 'GOLD', 1, format: _col2),
      PrintCommand.leftRight('Next Tier:', 'PLATINUM', 0, format: _col2),
      PrintCommand.leftRight('Points Needed:', '747', 0, format: _col2),
      PrintCommand.newLine(),
      PrintCommand.custom('Earn 747 more points to reach', 0, 1),
      PrintCommand.custom('PLATINUM status!', 0, 1),
      PrintCommand.newLine(),
      PrintCommand.custom(_sep, 0, 1),

      // ── Order breakdown (4-column) ──────────────────────────────────────
      PrintCommand.newLine(),
      PrintCommand.custom('ORDER BREAKDOWN', 1, 1),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.fourColumn('Cat', 'Items', 'Qty', 'Amt', 1,
          format: _col4),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.fourColumn('Drinks', '10', '20', '\$74.50', 0,
          format: _col4),
      PrintCommand.fourColumn('Starter', '8', '11', '\$71.50', 0,
          format: _col4),
      PrintCommand.fourColumn('Main', '12', '15', '\$251.00', 0,
          format: _col4),
      PrintCommand.fourColumn('Sides', '8', '15', '\$56.00', 0,
          format: _col4),
      PrintCommand.fourColumn('Dessert', '8', '12', '\$78.00', 0,
          format: _col4),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.fourColumn('TOTAL', '46', '73', '\$542.50', 1,
          format: _col4),
      PrintCommand.newLine(),
      PrintCommand.custom(_sep, 0, 1),

      // ── Nutritional summary ─────────────────────────────────────────────
      PrintCommand.newLine(),
      PrintCommand.custom('NUTRITIONAL SUMMARY', 1, 1),
      PrintCommand.custom('(estimated per serving)', 0, 1),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.leftRight('Avg Calories:', '~680 kcal', 0, format: _col2),
      PrintCommand.leftRight('Avg Protein:', '~32g', 0, format: _col2),
      PrintCommand.leftRight('Avg Carbs:', '~58g', 0, format: _col2),
      PrintCommand.leftRight('Avg Fat:', '~28g', 0, format: _col2),
      PrintCommand.newLine(),
      PrintCommand.custom('Allergens: Gluten, Dairy,', 0, 0),
      PrintCommand.custom('Nuts, Shellfish, Eggs, Soy', 0, 0),
      PrintCommand.custom('Please inform staff of any', 0, 0),
      PrintCommand.custom('food allergies or dietary', 0, 0),
      PrintCommand.custom('requirements.', 0, 0),
      PrintCommand.newLine(),
      PrintCommand.custom(_sep, 0, 1),

      // ── Terms & conditions ──────────────────────────────────────────────
      PrintCommand.newLine(),
      PrintCommand.custom('TERMS & CONDITIONS', 1, 1),
      PrintCommand.custom(_dot, 0, 1),
      PrintCommand.custom('1. All prices include VAT', 0, 0),
      PrintCommand.custom('   unless otherwise stated.', 0, 0),
      PrintCommand.custom('2. A 10% service charge is', 0, 0),
      PrintCommand.custom('   added for parties of 4+.', 0, 0),
      PrintCommand.custom('3. Please retain this receipt', 0, 0),
      PrintCommand.custom('   for your records.', 0, 0),
      PrintCommand.custom('4. Complaints must be raised', 0, 0),
      PrintCommand.custom('   within 24 hours.', 0, 0),
      PrintCommand.custom('5. Gift cards & vouchers are', 0, 0),
      PrintCommand.custom('   non-refundable.', 0, 0),
      PrintCommand.custom('6. We are not responsible for', 0, 0),
      PrintCommand.custom('   personal items left behind.', 0, 0),
      PrintCommand.custom('7. Menu items are subject to', 0, 0),
      PrintCommand.custom('   availability.', 0, 0),
      PrintCommand.custom('8. Management reserves the', 0, 0),
      PrintCommand.custom('   right to refuse service.', 0, 0),
      PrintCommand.newLine(),
      PrintCommand.custom(_sep, 0, 1), 
      PrintCommand.newLine(),
      PrintCommand.paperCut(),
    ]);
  }

  /// Legacy print — individual method calls (slower, kept for comparison).
  Future<void> sampleLegacy() async {
    final isConnected = await bluetooth.isConnected ?? false;
    if (!isConnected) return;

    await bluetooth.printNewLine();
    await bluetooth.printCustom('DRAGO PRINTER', 3, 1);
    await bluetooth.printCustom('Legacy Receipt', 1, 1);
    await bluetooth.printNewLine();

    await bluetooth.printLeftRight('LEFT', 'RIGHT', 0);
    await bluetooth.printLeftRight('LEFT', 'RIGHT', 1,
        format: '%-15s %15s %n');
    await bluetooth.printNewLine();

    await bluetooth.print3Column('Col1', 'Col2', 'Col3', 1);
    await bluetooth.print3Column('Col1', 'Col2', 'Col3', 1,
        format: '%-10s %10s %10s %n');
    await bluetooth.printNewLine();

    await bluetooth.print4Column('Col1', 'Col2', 'Col3', 'Col4', 1);
    await bluetooth.print4Column('Col1', 'Col2', 'Col3', 'Col4', 1,
        format: '%-8s %7s %7s %7s %n');
    await bluetooth.printNewLine();

    final testString = ' čĆžŽšŠ-H-ščđ';
    await bluetooth.printCustom(testString, 1, 1, charset: 'windows-1250');
    await bluetooth.printLeftRight('Številka:', '18000001', 1,
        charset: 'windows-1250');
    await bluetooth.printNewLine();

    await bluetooth.printCustom('Thank You', 2, 1);
    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
    await bluetooth.paperCut();
  }
}
