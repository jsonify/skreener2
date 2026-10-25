using System.Runtime.InteropServices;
using Windows.Foundation.Metadata;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace Skreener.App.Capture;

/// <summary>
/// The COM glue Windows.Graphics.Capture needs from a desktop app: a WinRT Direct3D device, capture items for an HWND
/// or HMONITOR (IGraphicsCaptureItemInterop), and turning the yellow capture border off.
/// These are plain vtable calls rather than CsWin32 COM projections: three methods do not justify the marshalling
/// layer, and the IIDs below are stable ABI.
/// </summary>
internal static unsafe partial class GraphicsCaptureInterop
{
    private static readonly Guid IidIGraphicsCaptureItemInterop = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private static readonly Guid IidIGraphicsCaptureItem = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid IidIDXGIDevice = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
    // Windows.Graphics.Capture.IGraphicsCaptureSession3 (IsBorderRequired, UniversalApiContract 12 / build 20348).
    // Not in the 10.0.19041 projection this app targets, so it is called through its ABI.
    private static readonly Guid IidIGraphicsCaptureSession3 = new("F2CDD966-22AE-5EA1-9596-3A289344C3BE");

    private const int D3D_DRIVER_TYPE_HARDWARE = 1;
    private const int D3D_DRIVER_TYPE_WARP = 5;
    private const uint D3D11_CREATE_DEVICE_BGRA_SUPPORT = 0x20;
    private const uint D3D11_SDK_VERSION = 7;

    [LibraryImport("d3d11.dll")]
    private static partial int D3D11CreateDevice(IntPtr adapter, int driverType, IntPtr software, uint flags,
        IntPtr featureLevels, uint featureLevelCount, uint sdkVersion, out IntPtr device, out int featureLevel, out IntPtr context);

    [LibraryImport("d3d11.dll")]
    private static partial int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    private static IObjectReference? s_itemFactory;
    private static IDirect3DDevice? s_device;

    /// <summary>One shared D3D11 device (hardware, or WARP when there is no usable GPU) for every capture.</summary>
    public static IDirect3DDevice Device => s_device ??= CreateDevice();

    /// <summary>Drops the shared device, e.g. after the GPU was reset; the next capture makes a new one.</summary>
    public static void ResetDevice()
    {
        (s_device as IDisposable)?.Dispose();
        s_device = null;
    }

    private static IDirect3DDevice CreateDevice()
    {
        int hr = D3D11CreateDevice(IntPtr.Zero, D3D_DRIVER_TYPE_HARDWARE, IntPtr.Zero, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            IntPtr.Zero, 0, D3D11_SDK_VERSION, out IntPtr device, out _, out IntPtr context);
        if (hr < 0)
        {
            hr = D3D11CreateDevice(IntPtr.Zero, D3D_DRIVER_TYPE_WARP, IntPtr.Zero, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                IntPtr.Zero, 0, D3D11_SDK_VERSION, out device, out _, out context);
        }
        Marshal.ThrowExceptionForHR(hr);
        try
        {
            Guid iid = IidIDXGIDevice;
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device, ref iid, out IntPtr dxgi));
            try
            {
                Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out IntPtr inspectable));
                try
                {
                    return MarshalInterface<IDirect3DDevice>.FromAbi(inspectable);
                }
                finally
                {
                    Marshal.Release(inspectable);
                }
            }
            finally
            {
                Marshal.Release(dxgi);
            }
        }
        finally
        {
            if (context != IntPtr.Zero) Marshal.Release(context);
            Marshal.Release(device);
        }
    }

    public static GraphicsCaptureItem CreateItemForWindow(IntPtr hwnd) => CreateItem(hwnd, forMonitor: false);

    public static GraphicsCaptureItem CreateItemForMonitor(IntPtr hmonitor) => CreateItem(hmonitor, forMonitor: true);

    private static GraphicsCaptureItem CreateItem(IntPtr handle, bool forMonitor)
    {
        s_itemFactory ??= ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem", IidIGraphicsCaptureItemInterop);
        IntPtr interop = s_itemFactory.ThisPtr;
        Guid iid = IidIGraphicsCaptureItem;
        IntPtr item;
        // IGraphicsCaptureItemInterop: CreateForWindow is vtable slot 3, CreateForMonitor slot 4.
        var create = (delegate* unmanaged[Stdcall]<IntPtr, IntPtr, Guid*, IntPtr*, int>)(*(void***)interop)[forMonitor ? 4 : 3];
        int hr = create(interop, handle, &iid, &item);
        GC.KeepAlive(s_itemFactory);
        Marshal.ThrowExceptionForHR(hr);
        try
        {
            return GraphicsCaptureItem.FromAbi(item);
        }
        finally
        {
            Marshal.Release(item);
        }
    }

    /// <summary>
    /// Turns off the yellow border Windows draws around what is being captured, where the OS allows it (Windows 11 /
    /// Server 2022 and later; earlier builds always draw it, briefly, while the one frame is grabbed). Returns whether it
    /// was turned off. [verify] Unpackaged apps should not need GraphicsCaptureAccess.RequestAccessAsync(Borderless).
    /// </summary>
    public static bool TryDisableBorder(GraphicsCaptureSession session)
    {
        if (!ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired")) return false;
        IntPtr inspectable = MarshalInspectable<GraphicsCaptureSession>.FromManaged(session);
        try
        {
            Guid iid = IidIGraphicsCaptureSession3;
            if (Marshal.QueryInterface(inspectable, ref iid, out IntPtr session3) < 0) return false;
            try
            {
                // IInspectable ends at slot 5; get_IsBorderRequired is slot 6, put_IsBorderRequired slot 7.
                var put = (delegate* unmanaged[Stdcall]<IntPtr, byte, int>)(*(void***)session3)[7];
                return put(session3, 0) >= 0;
            }
            finally
            {
                Marshal.Release(session3);
            }
        }
        finally
        {
            Marshal.Release(inspectable);
        }
    }
}
