/**
 * Media saving — ohos compliant sinks.
 * - Gallery: photoAccessHelper with SaveButton security-component temp authorization
 *   (call within the click handler's authorization window, files already on disk).
 * - Files: DocumentViewPicker.save returns user-authorized URIs.
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { QueueItem } from './DownloadQueue';

export class MediaSaver {
  /** Copy finished temp files into the media library (requires temp authorization). */
  static async saveToGallery(context: Context, items: QueueItem[]): Promise<number> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    let saved = 0;
    try {
      for (const item of items) {
        if (item.tempPath.length === 0 || item.state !== 2) {
          continue;
        }
        try {
          const src = fileIo.openSync(item.tempPath, fileIo.OpenMode.READ_ONLY);
          let request: photoAccessHelper.PhotoAssetChangeRequest;
          if (item.isVideo) {
            request = photoAccessHelper.PhotoAssetChangeRequest.createVideoAssetRequest(src.fd);
          } else {
            request = photoAccessHelper.PhotoAssetChangeRequest.createImageAssetRequest(src.fd);
          }
          request.setTitle(item.displayName);
          await helper.applyChanges(request);
          fileIo.closeSync(src.fd);
          saved++;
        } catch (e) {
          // Continue with remaining items; report partial success.
        }
      }
    } finally {
      helper.release();
    }
    return saved;
  }

  /** One save dialog for all items; returns URIs written. */
  static async saveToFiles(context: Context, items: QueueItem[]): Promise<number> {
    const documentSaveOptions = new picker.DocumentSaveOptions();
    const names: string[] = [];
    for (const item of items) {
      if (item.tempPath.length > 0 && item.state === 2) {
        names.push(item.displayName);
      }
    }
    if (names.length === 0) {
      return 0;
    }
    documentSaveOptions.newFileNames = names;
    documentSaveOptions.fileSuffixChoices = [];
    const docPicker = new picker.DocumentViewPicker();
    const uris = await docPicker.save(documentSaveOptions);
    if (uris === undefined || uris.length === 0) {
      return 0;
    }
    let saved = 0;
    for (let i = 0; i < uris.length && i < names.length; i++) {
      const srcItem = items.find((it: QueueItem): boolean => it.displayName === names[i]);
      if (srcItem === null) {
        continue;
      }
      try {
        const src = fileIo.openSync(srcItem.tempPath, fileIo.OpenMode.READ_ONLY);
        const dst = fileIo.openSync(uris[i], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        fileIo.copyFileSync(src.fd, dst.fd);
        fileIo.closeSync(src.fd);
        fileIo.closeSync(dst.fd);
        saved++;
      } catch (e) {
        // Skip failures.
      }
    }
    return saved;
  }

  /** Save a plain text file (note info TXT/MD) via the picker. */
  static async saveTextFile(context: Context, fileName: string, content: string): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const docPicker = new picker.DocumentViewPicker();
    try {
      const uris = await docPicker.save(options);
      if (uris === undefined || uris.length === 0) {
        return false;
      }
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, content);
      fileIo.closeSync(file.fd);
      return true;
    } catch (e) {
      return false;
    }
  }
}
