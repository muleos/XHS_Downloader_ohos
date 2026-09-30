/**
 * Media saving — ohos boundary port of data/storage/AndroidStorageSink.kt.
 * Archive folders map to gallery albums (author/note/xhsdn); names are deduped;
 * publish timestamp is applied best-effort (title always, date when supported).
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { dataSharePredicates } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { MediaFileType } from '../core/MediaFileType';
import { DownloadOptions } from '../core/models';

export class StoredOutput {
  uri: string = '';
  name: string = '';
  skipped: boolean = false;
}

/** One cached temp file to be copied into a user-chosen folder. */
export class FolderSaveRequest {
  path: string = '';
  name: string = '';
}

export class MediaSaver {
  /** Publish one downloaded temp file into the gallery (or custom picker flow). */
  static async storeArchived(context: Context, path: string, type: MediaFileType, requestedName: string,
    folders: string[], options: DownloadOptions, mediaId: string): Promise<StoredOutput> {
    const out = new StoredOutput();
    const name = await MediaSaver.uniqueName(context, requestedName);
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const isVideo = type.mimeType.startsWith('video/');
    try {
      const assetUri = fileUri.getUriFromPath(path);
      let changeRequest: photoAccessHelper.MediaAssetChangeRequest;
      if (isVideo) {
        changeRequest = photoAccessHelper.MediaAssetChangeRequest.createVideoAssetRequest(context, assetUri);
      } else {
        changeRequest = photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, assetUri);
      }
      changeRequest.setTitle(name.substring(0, name.lastIndexOf('.')));
      await helper.applyChanges(changeRequest);
      // Resolve the created asset URI (best effort) by title.
      try {
        const pred = new dataSharePredicates.DataSharePredicates();
        pred.equalTo('title', name.substring(0, name.lastIndexOf('.')));
        const fetchOptions: photoAccessHelper.FetchOptions = {
          fetchColumns: ['title'],
          predicates: pred
        };
        const result = await helper.getAssets(fetchOptions);
        if (result.getCount() > 0) {
          const asset = await result.getFirstObject();
          out.uri = asset.uri;
        }
        result.close();
      } catch (e) {
        // Asset is saved even if the URI lookup fails.
      }
      out.name = name;
      // Archive folders → albums (best-effort); unsupported on this API level,
      // so the asset lands in the default album.
      return out;
    } catch (e) {
      const detail = e instanceof Error ? e.message : String(e);
      throw new Error('gallery save failed: ' + detail);
    }
  }

  /**
   * Publish a batch of cached files to the gallery via the system creation
   * dialog (user confirms once per chunk; no prior permission needed).
   * Returns the number of assets actually created. Large batches are chunked
   * because the dialog rejects oversized URI lists; on chunk failure the
   * remaining files are retried one dialog per file.
   */
  static async storeGalleryBatch(context: Context, files: FolderSaveRequest[]): Promise<number> {
    if (files.length === 0) {
      return 0;
    }
    const chunkSize = 9;
    let saved = 0;
    for (let start = 0; start < files.length; start += chunkSize) {
      const end = Math.min(start + chunkSize, files.length);
      const chunk = files.slice(start, end);
      saved += await MediaSaver.storeGalleryChunk(context, chunk, chunkSize > 1);
    }
    return saved;
  }

  private static async storeGalleryChunk(context: Context, files: FolderSaveRequest[],
    allowPerFileFallback: boolean): Promise<number> {
    if (files.length === 0) {
      return 0;
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const srcUris: string[] = [];
    const configs: photoAccessHelper.PhotoCreationConfig[] = [];
    for (const f of files) {
      const dot = f.name.lastIndexOf('.');
      const ext = dot > 0 ? f.name.substring(dot + 1).toLowerCase() : 'jpg';
      let title = dot > 0 ? f.name.substring(0, dot) : f.name;
      if (title.length > 200) {
        title = title.substring(0, 200);
      }
      srcUris.push(fileUri.getUriFromPath(f.path));
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: title,
        fileNameExtension: ext,
        photoType: ext === 'mp4' || ext === 'mov' ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
      };
      configs.push(config);
    }
    try {
      const uris = await helper.showAssetsCreationDialog(srcUris, configs);
      return uris === undefined ? 0 : uris.length;
    } catch (e) {
      if (!allowPerFileFallback || files.length <= 1) {
        throw e instanceof Error ? e : new Error(String(e));
      }
      // Batch dialog rejected (bad parameter / too many URIs / transient
      // window error) — retry one file per dialog.
      let saved = 0;
      for (const f of files) {
        const single: FolderSaveRequest[] = [f];
        try {
          saved += await MediaSaver.storeGalleryChunk(context, single, false);
        } catch (e2) {
          // Skip this file; keep saving the rest.
        }
      }
      return saved;
    }
  }

  /**
   * Copy cached files into a folder chosen by the user (system directory).
   * Tries one batch dialog first; falls back to per-file dialogs when the
   * picker only returns a single destination URI.
   */
  static async storeToFolder(files: FolderSaveRequest[]): Promise<StoredOutput[]> {
    const results: StoredOutput[] = [];
    if (files.length === 0) {
      return results;
    }
    const docPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = files.map((f: FolderSaveRequest): string => f.name);
    let uris: string[] = [];
    try {
      const saved = await docPicker.save(options);
      uris = saved === undefined ? [] : saved;
    } catch (e) {
      uris = [];
    }
    if (uris.length === files.length) {
      for (let i = 0; i < files.length; i++) {
        await MediaSaver.copyToUri(files[i].path, uris[i]);
        const out = new StoredOutput();
        out.uri = uris[i];
        out.name = files[i].name;
        results.push(out);
      }
      return results;
    }
    if (uris.length > 0) {
      // Unexpected partial result — treat as cancelled to avoid wrong mapping.
      return results;
    }
    // Batch dialog unsupported or cancelled without intent; per-file fallback.
    for (const f of files) {
      const single = new picker.DocumentSaveOptions();
      single.newFileNames = [f.name];
      try {
        const saved = await docPicker.save(single);
        if (saved === undefined || saved.length === 0) {
          continue;
        }
        await MediaSaver.copyToUri(f.path, saved[0]);
        const out = new StoredOutput();
        out.uri = saved[0];
        out.name = f.name;
        results.push(out);
      } catch (e) {
        // Skip this file; keep saving the rest.
      }
    }
    return results;
  }

  private static copyToUri(src: string, destUri: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      try {
        const s = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
        const d = fileIo.openSync(destUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        fileIo.copyFile(s.fd, d.fd).then(() => {
          fileIo.closeSync(s.fd);
          fileIo.closeSync(d.fd);
          resolve();
        }).catch((e: BusinessError) => {
          try {
            fileIo.closeSync(s.fd);
            fileIo.closeSync(d.fd);
          } catch (e2) {
          }
          reject(e instanceof Error ? e : new Error(String(e)));
        });
      } catch (e) {
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  /** Save a text document (note info) through the picker; folders are flattened into the name. */
  static async storeText(context: Context, folders: string[], fileName: string, content: string): Promise<StoredOutput> {
    const out = new StoredOutput();
    const prefix = folders.length > 0 ? folders.join('_') + '_' : '';
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [prefix + fileName];
    const docPicker = new picker.DocumentViewPicker();
    const uris = await docPicker.save(options);
    if (uris === undefined || uris.length === 0) {
      out.skipped = true;
      return out;
    }
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, content);
    fileIo.closeSync(file.fd);
    out.uri = uris[0];
    out.name = fileName;
    return out;
  }

  /** "name (n).ext" dedupe against the media library. */
  private static async uniqueName(context: Context, requested: string): Promise<string> {
    const dot = requested.lastIndexOf('.');
    const base = dot > 0 ? requested.substring(0, dot) : requested;
    const ext = dot > 0 ? requested.substring(dot) : '';
    let candidate = requested;
    let index = 1;
    while (await MediaSaver.existsInLibrary(context, candidate) && index < 100) {
      candidate = base + ' (' + index + ')' + ext;
      index++;
    }
    return candidate;
  }

  private static async existsInLibrary(context: Context, displayName: string): Promise<boolean> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const pred = new dataSharePredicates.DataSharePredicates();
      pred.equalTo('title', displayName.substring(0, displayName.lastIndexOf('.')));
      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: ['title'],
        predicates: pred
      };
      const result = await helper.getAssets(fetchOptions);
      const count = result.getCount();
      result.close();
      return count > 0;
    } catch (e) {
      return false;
    }
  }
}
