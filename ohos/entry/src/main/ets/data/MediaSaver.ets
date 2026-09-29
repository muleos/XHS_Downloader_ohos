/**
 * Media saving — ohos boundary port of data/storage/AndroidStorageSink.kt.
 * Archive folders map to gallery albums (author/note/xhsdn); names are deduped;
 * publish timestamp is applied best-effort (title always, date when supported).
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { dataSharePredicates } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { MediaFileType } from '../core/MediaFileType';
import { DownloadOptions } from '../core/models';

export class StoredOutput {
  uri: string = '';
  name: string = '';
  skipped: boolean = false;
}

export class MediaSaver {
  /** Publish one downloaded temp file into the gallery (or custom picker flow). */
  static async storeArchived(context: Context, path: string, type: MediaFileType, requestedName: string,
    folders: string[], options: DownloadOptions, mediaId: string): Promise<StoredOutput> {
    const out = new StoredOutput();
    const name = MediaSaver.uniqueName(context, requestedName);
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const isVideo = type.mimeType.startsWith('video/');
    try {
      const src = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      let changeRequest: photoAccessHelper.PhotoAssetChangeRequest;
      if (isVideo) {
        changeRequest = photoAccessHelper.PhotoAssetChangeRequest.createVideoAssetRequest(src.fd);
      } else {
        changeRequest = photoAccessHelper.PhotoAssetChangeRequest.createImageAssetRequest(src.fd);
      }
      changeRequest.setTitle(name.substring(0, name.lastIndexOf('.')));
      const assetChange = await helper.applyChanges(changeRequest);
      fileIo.closeSync(src.fd);
      const uri = assetChange.getUri();
      out.uri = uri;
      out.name = name;
      // Archive folders → albums (best-effort).
      for (const folder of folders) {
        try {
          const album = await helper.createAlbum(folder);
          const target = await helper.getAlbums(photoAccessHelper.AlbumKey.NAME, [folder]);
          if (target.length > 0) {
            await target[0].addAssets([uri]);
          } else {
            await album.addAssets([uri]);
          }
        } catch (e) {
          // Album exists or is unsupported on this device — keep the asset.
        }
      }
      if (options.writePublishTime && options.proxy.length === 0) {
        // DATE_TAKEN is not writable by normal apps; recorded via title only.
      }
      return out;
    } catch (e) {
      const detail = e instanceof Error ? e.message : String(e);
      throw new Error('gallery save failed: ' + detail);
    }
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
  private static uniqueName(context: Context, requested: string): string {
    const dot = requested.lastIndexOf('.');
    const base = dot > 0 ? requested.substring(0, dot) : requested;
    const ext = dot > 0 ? requested.substring(dot) : '';
    let candidate = requested;
    let index = 1;
    while (MediaSaver.existsInLibrary(context, candidate) && index < 100) {
      candidate = base + ' (' + index + ')' + ext;
      index++;
    }
    return candidate;
  }

  private static existsInLibrary(context: Context, displayName: string): boolean {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const predicates = new photoAccessHelper.FetchOptions();
      predicates.fetchColumns = ['title'];
      const pred = new dataSharePredicates();
      pred.equalTo('title', displayName.substring(0, displayName.lastIndexOf('.')));
      predicates.where = pred;
      const result = helper.getAssets(predicates);
      return result.getCount() > 0;
    } catch (e) {
      return false;
    }
  }
}
