using Skreener.App.Capture;

namespace Skreener.App.Shell;

/// <summary>Stand-in until the real CaptureService lands: never captures, just says so.</summary>
internal sealed class PlaceholderCaptureService : ICaptureService
{
    private readonly Notifier _notifier;

    public PlaceholderCaptureService(Notifier notifier) => _notifier = notifier;

    public Task<CaptureResult?> CaptureAsync(CaptureKind kind, CancellationToken cancellationToken = default)
    {
        _notifier.Show("Capture not implemented yet", $"{kind} capture is not available in this build.");
        return Task.FromResult<CaptureResult?>(null);
    }
}
