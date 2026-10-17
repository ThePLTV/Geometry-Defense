package org.thepltv.geometrydefense.reports;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;

/** Read-only URI grants expose only the exported ZIP, never game saves or arbitrary paths. */
public final class ReportProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    private File resolve(Uri uri) throws FileNotFoundException {
        if (!"/report/GeometryDefense-03-report.zip".equals(uri.getPath())) throw new FileNotFoundException("Unknown report");
        File file = new File(getContext().getCacheDir(), "geometry_reports/GeometryDefense-03-report.zip");
        if (!file.isFile()) throw new FileNotFoundException("Report unavailable");
        return file;
    }
    @Override public String getType(Uri uri) { return "application/zip"; }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Read only");
        return ParcelFileDescriptor.open(resolve(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        try {
            File file=resolve(uri);
            String[] columns=projection==null?new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE}:projection;
            MatrixCursor cursor=new MatrixCursor(columns); Object[] row=new Object[columns.length];
            for(int i=0;i<columns.length;i++) {
                if(OpenableColumns.DISPLAY_NAME.equals(columns[i])) row[i]=file.getName();
                else if(OpenableColumns.SIZE.equals(columns[i])) row[i]=file.length();
            }
            cursor.addRow(row); return cursor;
        } catch(FileNotFoundException e) { return null; }
    }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException("Read only"); }
    @Override public int delete(Uri uri,String selection,String[] args) { throw new UnsupportedOperationException("Read only"); }
    @Override public int update(Uri uri,ContentValues values,String selection,String[] args) { throw new UnsupportedOperationException("Read only"); }
}
