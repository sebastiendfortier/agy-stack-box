/* X11 MIT-SHM cannot attach across the instance IPC namespace.
   GDK turns the resulting BadAccess into a fatal error and aborts Electron.
   Report the extension as missing so clients use plain X images instead. */
#include <X11/Xlib.h>
#include <X11/extensions/XShm.h>

Bool XShmQueryExtension(Display *display) {
  (void)display;
  return False;
}

Bool XShmQueryVersion(Display *display, int *major, int *minor, Bool *pixmaps) {
  (void)display;
  if (major)
    *major = 0;
  if (minor)
    *minor = 0;
  if (pixmaps)
    *pixmaps = False;
  return False;
}

Status XShmAttach(Display *display, XShmSegmentInfo *shminfo) {
  (void)display;
  (void)shminfo;
  return 0;
}
