package org.thepltv.geometrydefense.reports;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

public final class ReportShare extends GodotPlugin {
    public ReportShare(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "ReportShare"; }
    private volatile String lastError = "";
    @UsedByGodot public String getLastError() { return lastError; }
    @UsedByGodot public String shareReport(String sourcePath) {
        Activity activity = getActivity();
        if (activity == null) return "Android activity unavailable";
        try {
            File source = new File(sourcePath).getCanonicalFile();
            File files = activity.getFilesDir().getCanonicalFile();
            File external = activity.getExternalFilesDir(null);
            boolean allowed = source.toPath().startsWith(files.toPath());
            if (external != null) allowed |= source.toPath().startsWith(external.getCanonicalFile().toPath());
            if (!allowed || !source.isFile() || !source.getName().endsWith(".zip")) return "Invalid report file";
            File folder = new File(activity.getCacheDir(), "geometry_reports");
            if (!folder.isDirectory() && !folder.mkdirs()) return "Cannot create report cache";
            File target = new File(folder, "GeometryDefense-04-report.zip");
            Files.copy(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING);
            Uri uri = new Uri.Builder().scheme("content").authority(activity.getPackageName()+".reports")
                .appendPath("report").appendPath(target.getName()).build();
            activity.runOnUiThread(() -> {
                try {
                    Intent send = new Intent(Intent.ACTION_SEND).setType("application/zip")
                        .putExtra(Intent.EXTRA_STREAM, uri)
                        .putExtra(Intent.EXTRA_SUBJECT, "Geometry Defense 0.4 diagnostics")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    send.setClipData(ClipData.newRawUri("Geometry Defense report", uri));
                    activity.startActivity(Intent.createChooser(send, "Отправить отчёт Geometry Defense"));
                    lastError = "";
                } catch (Exception e) { lastError = e.toString(); Log.e("ReportShare", "Sharesheet failed", e); }
            });
            return "";
        } catch (Exception e) { lastError=e.toString(); return lastError; }
    }
}
