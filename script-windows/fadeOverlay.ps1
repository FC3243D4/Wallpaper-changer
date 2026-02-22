param(
    [string]$ImagePath,
    [int]$Left,
    [int]$Top,
    [int]$Width,
    [int]$Height,
    [int]$Duration = 700
)

Add-Type -AssemblyName PresentationFramework

$window = New-Object Windows.Window
$window.WindowStyle = "None"
$window.ResizeMode = "NoResize"
$window.Left = $Left
$window.Top = $Top
$window.Width = $Width
$window.Height = $Height
$window.Topmost = $true
$window.AllowsTransparency = $true
$window.Background = "Black"

$image = New-Object Windows.Controls.Image
$image.Source = New-Object Windows.Media.Imaging.BitmapImage([Uri]$ImagePath)
$image.Stretch = "UniformToFill"

$window.Content = $image
$window.Show()

$anim = New-Object Windows.Media.Animation.DoubleAnimation
$anim.From = 1
$anim.To = 0
$anim.Duration = [TimeSpan]::FromMilliseconds($Duration)

$anim.add_Completed({ $window.Close() })
$window.BeginAnimation([Windows.UIElement]::OpacityProperty, $anim)

[Windows.Threading.Dispatcher]::Run()