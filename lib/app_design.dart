import 'dart:math' as math;
import 'package:flutter/material.dart';

const studioInk=Color(0xff242334);
const studioMuted=Color(0xff706e85);
const studioPurple=Color(0xff6548e8);

ThemeData studioTheme() {
  final scheme=ColorScheme.fromSeed(seedColor:studioPurple,brightness:Brightness.light,
    primary:studioPurple,secondary:const Color(0xff167d76),surface:Colors.white);
  final base=ThemeData(useMaterial3:true,colorScheme:scheme,scaffoldBackgroundColor:const Color(0xfff5f4f9));
  return base.copyWith(
    textTheme:base.textTheme.apply(bodyColor:studioInk,displayColor:studioInk),
    appBarTheme:const AppBarTheme(backgroundColor:Color(0xfff5f4f9),foregroundColor:studioInk,
      surfaceTintColor:Colors.transparent,centerTitle:false,titleTextStyle:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:studioInk)),
    cardTheme:CardThemeData(color:Colors.white,surfaceTintColor:Colors.transparent,elevation:0,
      margin:const EdgeInsets.symmetric(vertical:7),shape:RoundedRectangleBorder(
        borderRadius:BorderRadius.circular(24),side:const BorderSide(color:Color(0xffe9e6f1)))),
    inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:const Color(0xfff4f2f8),
      labelStyle:const TextStyle(color:studioMuted),contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:16),
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none),
      focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:const BorderSide(color:studioPurple,width:1.5))),
    filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(minimumSize:const Size(48,52),
      textStyle:const TextStyle(fontWeight:FontWeight.w700,fontSize:15),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)))),
    outlinedButtonTheme:OutlinedButtonThemeData(style:OutlinedButton.styleFrom(minimumSize:const Size(48,48),
      side:const BorderSide(color:Color(0xffdcd7ee)),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)))),
    textButtonTheme:TextButtonThemeData(style:TextButton.styleFrom(textStyle:const TextStyle(fontWeight:FontWeight.w700))),
    dividerTheme:const DividerThemeData(color:Color(0xffedeaf3),space:24),
    chipTheme:base.chipTheme.copyWith(side:BorderSide.none,backgroundColor:const Color(0xffeeeaf9),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
    dialogTheme:DialogThemeData(backgroundColor:Colors.white,surfaceTintColor:Colors.transparent,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(28))),
    snackBarTheme:SnackBarThemeData(behavior:SnackBarBehavior.floating,backgroundColor:studioInk,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16))),
  );
}

class StudioHeading extends StatelessWidget {
  const StudioHeading(this.title,{super.key,this.subtitle});
  final String title;final String? subtitle;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:22,bottom:12),child:Row(children:[
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:21,letterSpacing:-.5)),
      if(subtitle!=null)...[const SizedBox(height:3),Text(subtitle!,style:const TextStyle(fontSize:13,color:studioMuted))],
    ])),
  ]));
}

class StudioHero extends StatelessWidget {
  const StudioHero({super.key,required this.onOpen});
  final VoidCallback onOpen;
  @override Widget build(BuildContext context)=>Container(
    decoration:BoxDecoration(borderRadius:BorderRadius.circular(28),
      gradient:const LinearGradient(colors:[Color(0xffede7ff),Color(0xffe8eaff)],begin:Alignment.topLeft,end:Alignment.bottomRight),
      border:Border.all(color:const Color(0xffe1d9fa))),
    child:ClipRRect(borderRadius:BorderRadius.circular(28),child:Padding(padding:const EdgeInsets.all(22),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
              decoration:BoxDecoration(color:Colors.white.withValues(alpha:.75),borderRadius:BorderRadius.circular(10)),
              child:const Text('DEIN DRUCKSTUDIO',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800,letterSpacing:1.4,color:studioPurple))),
            const SizedBox(height:17),const Text('Deine Idee.\nIn Bestform.',style:TextStyle(fontSize:32,height:1.08,fontWeight:FontWeight.w800,letterSpacing:-1.2)),
            const SizedBox(height:12),const Text('Neues Druckprojekt',style:TextStyle(fontSize:14,color:studioMuted,fontWeight:FontWeight.w600)),
          ])),
          const SizedBox(width:8),const SizedBox(width:105,height:150,child:CustomPaint(painter:StudioObjectPainter())),
        ]),
        const SizedBox(height:22),
        SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:onOpen,
          icon:const Icon(Icons.add_rounded),label:const Text('STL / 3MF öffnen'))),
      ]))));
}

class StudioObjectPainter extends CustomPainter {
  const StudioObjectPainter();
  @override void paint(Canvas canvas,Size size) {
    final sx=size.width/105,sy=size.height/150;canvas.save();canvas.scale(sx,sy);
    final paint=Paint();
    for(var y=20.0;y<145;y+=12)for(var x=4.0;x<105;x+=12){canvas.drawCircle(Offset(x,y),.8,paint..color=const Color(0xffc8beea));}
    canvas.drawOval(const Rect.fromLTWH(5,116,96,20),paint..color=const Color(0xffd3c8f2));
    final top=Path()..moveTo(53,24)..lineTo(97,50)..lineTo(53,76)..lineTo(9,50)..close();
    final left=Path()..moveTo(9,50)..lineTo(53,76)..lineTo(53,124)..lineTo(9,98)..close();
    final right=Path()..moveTo(53,76)..lineTo(97,50)..lineTo(97,98)..lineTo(53,124)..close();
    canvas.drawPath(left,paint..color=const Color(0xff8e71f5));
    canvas.drawPath(right,paint..color=const Color(0xff5936c8));
    canvas.drawPath(top,paint..color=const Color(0xffb9a6ff));
    paint..color=Colors.white.withValues(alpha:.35)..style=PaintingStyle.stroke..strokeWidth=1;
    for(var i=1;i<9;i++){
      final y=50+i*5.3;canvas.drawLine(Offset(9,y),Offset(53,y+26),paint);canvas.drawLine(Offset(53,y+26),Offset(97,y),paint);
    }
    paint.style=PaintingStyle.fill;
    canvas.drawCircle(const Offset(88,22),14,paint..color=const Color(0xffffa57d));
    paint..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round;
    canvas.drawLine(const Offset(82,22),const Offset(86,26),paint);canvas.drawLine(const Offset(86,26),const Offset(94,18),paint);
    canvas.restore();
  }
  @override bool shouldRepaint(covariant StudioObjectPainter oldDelegate)=>false;
}

class StudioTool extends StatelessWidget {
  const StudioTool({super.key,required this.title,required this.subtitle,required this.icon,required this.color,required this.onTap});
  final String title,subtitle;final IconData icon;final Color color;final VoidCallback onTap;
  @override Widget build(BuildContext context)=>Material(color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(23),side:const BorderSide(color:Color(0xffe9e6f1))),
    clipBehavior:Clip.antiAlias,child:InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.all(16),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:color.withValues(alpha:.12),
          borderRadius:BorderRadius.circular(14)),child:Icon(icon,color:color,size:25)),const Spacer(),
          const Icon(Icons.north_east_rounded,size:17,color:studioMuted)]),
        const SizedBox(height:18),Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
        const SizedBox(height:5),Text(subtitle,style:const TextStyle(fontSize:12,color:studioMuted,height:1.4)),
      ]))));
}

class StudioTools extends StatelessWidget {
  const StudioTools({super.key,required this.children});
  final List<Widget> children;
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,c){
    final columns=c.maxWidth<310?1:c.maxWidth>720?4:2;
    final width=(c.maxWidth-(columns-1)*12)/columns;
    return Wrap(spacing:12,runSpacing:12,children:[for(final child in children)SizedBox(width:width,child:child)]);
  });
}

class StudioViewportPainter extends CustomPainter {
  const StudioViewportPainter();
  @override void paint(Canvas canvas,Size size){
    canvas.drawRect(Offset.zero&size,Paint()..shader=const LinearGradient(colors:[Color(0xff29273e),Color(0xff171627)],
      begin:Alignment.topLeft,end:Alignment.bottomRight).createShader(Offset.zero&size));
    final paint=Paint()..color=const Color(0xff464059)..strokeWidth=.7;
    final horizon=size.height*.58,center=size.width/2;
    for(int i=-7;i<=7;i++)canvas.drawLine(Offset(center+i*22,horizon),Offset(center+i*90,size.height),paint);
    for(int i=0;i<8;i++){
      final y=horizon+(size.height-horizon)*math.pow(i/7,1.8).toDouble();
      canvas.drawLine(Offset(0,y),Offset(size.width,y),paint);
    }
  }
  @override bool shouldRepaint(covariant StudioViewportPainter oldDelegate)=>false;
}
