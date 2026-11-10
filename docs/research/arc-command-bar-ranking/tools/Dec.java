import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
public class Dec extends GhidraScript {
  @Override public void run() throws Exception {
    String[] a = getScriptArgs();
    List<String> addrs = Files.readAllLines(Paths.get(a[0]));
    String outDir = a[1];
    DecompInterface d = new DecompInterface();
    DecompileOptions o = new DecompileOptions();
    d.setOptions(o);
    d.openProgram(currentProgram);
    for (String s : addrs) {
      s = s.trim(); if (s.isEmpty()) continue;
      Address ad = toAddr(s);
      disassemble(ad);
      Function f = getFunctionAt(ad);
      if (f == null) f = createFunction(ad, "F_" + s);
      if (f == null) { println("no function " + s); continue; }
      DecompileResults r = d.decompileFunction(f, 600, monitor);
      String txt = r.decompileCompleted() ? r.getDecompiledFunction().getC() : ("failed: " + r.getErrorMessage());
      Files.write(Paths.get(outDir, s + ".c"), txt.getBytes());
      println("done " + s + " " + txt.length());
    }
  }
}
