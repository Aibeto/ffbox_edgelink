/// 任务操作。覆盖 FFBox 任务生命周期全部操作，便于后续逐步开放 UI。
enum TaskOperation {
  create,
  start,
  ready,
  pause,
  resume,
  reset,
  delete,
  setParameters,
  mergeUpload,
  setUploadStatus,
}
