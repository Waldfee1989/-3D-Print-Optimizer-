import 'plate_geometry.dart';

class PlateSnapshot {
  PlateSnapshot(List<PlatePlacement> parts,this.selected):parts=List.unmodifiable(parts);
  final List<PlatePlacement> parts;
  final int selected;
}
class WorkspaceHistory {
  final List<PlateSnapshot> _undo=[],_redo=[];
  bool get canUndo=>_undo.isNotEmpty;
  bool get canRedo=>_redo.isNotEmpty;
  void record(PlateSnapshot before){
    _undo.add(before);_redo.clear();
    while(_undo.length>25 || (_undo.length>1&&_bytes()>180*1024*1024)){_undo.removeAt(0);}
  }
  int _bytes(){
    final buffers=Set<Object>.identity();var bytes=0;
    for(final state in [..._undo,..._redo])for(final p in state.parts){
      if(buffers.add(p.part.vertices))bytes+=p.part.vertices.lengthInBytes;
    }
    return bytes;
  }
  PlateSnapshot undo(PlateSnapshot current){if(!canUndo)return current;_redo.add(current);return _undo.removeLast();}
  PlateSnapshot redo(PlateSnapshot current){if(!canRedo)return current;_undo.add(current);return _redo.removeLast();}
}
