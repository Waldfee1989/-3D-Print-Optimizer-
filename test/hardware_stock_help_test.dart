import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_optimizer/printer_setup.dart';
import 'package:print_optimizer/nozzles.dart';
import 'package:print_optimizer/low_stock.dart';
import 'package:print_optimizer/help_chat.dart';
import 'package:print_optimizer/project_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Selected printer retains its own bed and unknown printers are not guessed',() async {
    SharedPreferences.setMockInitialValues({});final prefs=await SharedPreferences.getInstance();
    expect(loadPrinterBed(prefs,'Anycubic Kobra S1')!.height,250);
    expect(loadPrinterBed(prefs,'Anderer Drucker'),isNull);
    await savePrinterBed(prefs,'Anderer Drucker',const PrinterBed(220,180,300));
    expect(loadPrinterBed(prefs,'Anderer Drucker')!.depth,180);
    expect(loadPrinterBed(prefs,'Anycubic Kobra S1')!.width,250);
  });
  test('Nozzle recommendation only uses available compatible stock and geometry adapts',() async {
    SharedPreferences.setMockInitialValues({});
    final seed=await loadNozzles(seedPrinter:'S1',seedDiameter:'0.4');expect(seed.single.diameter,.4);
    final rows=[...seed,const OwnedNozzle(id:'small',printer:'S1',diameter:.25,material:'Messing',quantity:1),
      const OwnedNozzle(id:'large',printer:'S1',diameter:.6,material:'Stahl',quantity:1),
      const OwnedNozzle(id:'empty',printer:'S1',diameter:.2,material:'Messing',quantity:0),
      const OwnedNozzle(id:'other',printer:'Other',diameter:.2,material:'Messing',quantity:10)];
    await saveNozzles(rows);
    expect(recommendOwnedNozzle(await loadNozzles(),'S1',fine:true,fast:false,functional:false)!.diameter,.25);
    expect(recommendOwnedNozzle(rows,'S1',fine:false,fast:true,functional:true)!.diameter,.6);
    expect(nozzleGeometry(.6,'Maximale Qualität').layer,.18);
    expect(nozzleGeometry(.6,'Maximale Qualität').line,.63);
  });
  test('Shopping list combines matching rolls, preserves barcodes and does not guess unknown amounts',() {
    Map<String,dynamic> roll(String code,Object grams,{String color='Schwarz'})=>{'brand':'SUNLU','material':'PLA','color':color,'barcode':code,'grams':grams};
    final stock=[roll('001',150),roll('001',100),roll('002',80),roll('003','NaN'),roll('1',0)];
    final low=reorderFilaments(stock,200);
    expect(low.map((p)=>p.barcode).toSet(),{'002','1'});
    expect(filamentBalances(stock).singleWhere((p)=>p.barcode=='001').grams,250);
    expect(filamentBalances(stock).singleWhere((p)=>p.barcode=='003').known,isFalse);
  });
  test('Offline help uses project temperatures and is honest about unknown questions',() {
    final p=PrintProject(id:'x',fileName:'x',dimensions:'10 mm',printer:'Anycubic Kobra S1',slicer:'Anycubic Slicer Next',nozzle:'.4');
    expect(answerPrintHelp('Welche Temperatur?',p),contains('205 °C'));
    expect(answerPrintHelp('Was ist Infill?',p),contains('Wände'));
    expect(answerPrintHelp('Wer gewinnt morgen im Lotto?',p),contains('kein frei antwortender KI-Dienst'));
  });
}
