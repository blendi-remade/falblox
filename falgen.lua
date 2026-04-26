-- falgen.lua
-- Roblox Studio plugin: 3D generation in Studio via fal.ai (Tripo P1)
--
-- Drop into %LOCALAPPDATA%\Roblox\Plugins\ and restart Studio.
-- BYO fal key — paste it into the widget the first time you open it.

if not plugin then
	warn("[falgen] not running as a plugin")
	return
end

local HttpService = game:GetService("HttpService")
local StudioService = game:GetService("StudioService")

local FAL_BASE = "https://queue.fal.run"
local FAL_STORAGE_INITIATE = "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
local TEXT_MODEL = "tripo3d/p1/text-to-3d"
local IMAGE_MODEL = "tripo3d/p1/image-to-3d"
local DEFAULT_FACE_LIMIT = 9000
local POLL_INTERVAL = 2
local MAX_IMAGE_BYTES = 4 * 1024 * 1024

-- ============================================================
-- Storage (plugin:SetSetting — plaintext on disk, BYO key only)
-- ============================================================
local function getKey()
	return plugin:GetSetting("fal_key") or ""
end
local function setKey(k)
	plugin:SetSetting("fal_key", k)
end

-- ============================================================
-- fal client
-- ============================================================
local function authHeaders()
	local key = getKey()
	if key == "" then
		error("FAL_KEY not set — paste it into the widget and click Save key.")
	end
	return {
		["Authorization"] = "Key " .. key,
		["Content-Type"] = "application/json",
		["Accept"] = "application/json",
	}
end

local function falSubmit(model, payload)
	local res = HttpService:RequestAsync({
		Url = FAL_BASE .. "/" .. model,
		Method = "POST",
		Headers = authHeaders(),
		Body = HttpService:JSONEncode(payload),
	})
	if not res.Success then
		error(string.format("submit %d %s — %s", res.StatusCode, res.StatusMessage, res.Body))
	end
	return HttpService:JSONDecode(res.Body)
end

local function falGet(url)
	local key = getKey()
	if key == "" then
		error("FAL_KEY not set.")
	end
	-- GETs only send Authorization; no Content-Type since there's no body.
	local res = HttpService:RequestAsync({
		Url = url,
		Method = "GET",
		Headers = {
			["Authorization"] = "Key " .. key,
			["Accept"] = "application/json",
		},
	})
	if not res.Success then
		error(string.format("GET %s → %d %s\nbody: %s", url, res.StatusCode, res.StatusMessage, res.Body or "(empty)"))
	end
	return HttpService:JSONDecode(res.Body)
end

local function falRunJob(model, payload, onLog)
	local sub = falSubmit(model, payload)
	local requestId = sub.request_id
	-- fal's submit response includes the canonical URLs to poll. For
	-- namespaced apps (e.g. tripo3d/p1/text-to-3d) the status path drops the
	-- leaf segment, so always trust these URLs over hand-built ones.
	local statusUrl = sub.status_url
	local responseUrl = sub.response_url
	if not statusUrl or not responseUrl then
		error("submit response missing status_url/response_url: " .. HttpService:JSONEncode(sub))
	end
	onLog("queued: " .. tostring(requestId))
	local lastStatus = nil
	while true do
		task.wait(POLL_INTERVAL)
		local st = falGet(statusUrl)
		if st.status ~= lastStatus then
			onLog("status: " .. tostring(st.status))
			lastStatus = st.status
		end
		if st.status == "COMPLETED" then
			return falGet(responseUrl)
		elseif st.status == "FAILED" or st.status == "CANCELLED" or st.status == "ERROR" then
			error("job " .. tostring(st.status) .. ": " .. HttpService:JSONEncode(st))
		end
	end
end

-- ============================================================
-- fal storage — initiate + PUT, returns a public file URL.
-- Mirrors what @fal-ai/client does in storage.ts.
-- ============================================================
local function redact(s)
	-- Strip key=… fragments from error bodies before printing.
	if not s then return "" end
	return (string.gsub(s, "[Kk][Ee][Yy]=[%w%-_]+", "key=<redacted>"))
end

local function falStorageUpload(bytes, fileName, mime)
	local key = getKey()
	if key == "" then
		error("FAL_KEY not set.")
	end

	-- 1. POST /storage/upload/initiate → { file_url, upload_url }
	local initRes = HttpService:RequestAsync({
		Url = FAL_STORAGE_INITIATE,
		Method = "POST",
		Headers = {
			["Authorization"] = "Key " .. key,
			["Content-Type"] = "application/json",
			["Accept"] = "application/json",
		},
		Body = HttpService:JSONEncode({
			content_type = mime,
			file_name = fileName,
		}),
	})
	if not initRes.Success then
		error(string.format("storage initiate %d %s — %s", initRes.StatusCode, initRes.StatusMessage, redact(initRes.Body)))
	end
	local init = HttpService:JSONDecode(initRes.Body)
	local uploadUrl = init.upload_url
	local fileUrl = init.file_url
	if not uploadUrl or not fileUrl then
		error("storage initiate missing upload_url/file_url: " .. redact(initRes.Body))
	end

	-- 2. PUT bytes to upload_url (signed URL — no auth header needed).
	local putRes = HttpService:RequestAsync({
		Url = uploadUrl,
		Method = "PUT",
		Headers = {
			["Content-Type"] = mime,
		},
		Body = bytes,
	})
	if not putRes.Success then
		error(string.format("storage PUT %d %s", putRes.StatusCode, putRes.StatusMessage))
	end

	return fileUrl
end

-- ============================================================
-- Result parsing
-- ============================================================
local function extractGlbUrl(result)
	if result.model_mesh and result.model_mesh.url and result.model_mesh.url ~= "" then
		return result.model_mesh.url
	end
	if result.model_urls then
		if result.model_urls.glb and result.model_urls.glb.url then
			return result.model_urls.glb.url
		end
		if result.model_urls.pbr_model and result.model_urls.pbr_model.url then
			return result.model_urls.pbr_model.url
		end
	end
	return nil
end

-- ============================================================
-- UI
-- ============================================================
local TOOLBAR = plugin:CreateToolbar("fal")
local BUTTON = TOOLBAR:CreateButton("falgen", "Generate 3D models with fal.ai", "")
BUTTON.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, false, false, 400, 620, 340, 480
)
local widget = plugin:CreateDockWidgetPluginGui("falgen.widget", widgetInfo)
widget.Title = "fal · 3D Generation"
widget.Name = "falgen"

BUTTON.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	BUTTON:SetActive(widget.Enabled)
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, 0)
scroll.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = widget

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = scroll

local order = 0
local function nextOrder()
	order = order + 1
	return order
end

local function header(text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(240, 240, 240)
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 16
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.LayoutOrder = nextOrder()
	lbl.Parent = scroll
	return lbl
end

local function muted(text, height)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, height or 18)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(160, 160, 160)
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.TextWrapped = true
	lbl.Text = text
	lbl.LayoutOrder = nextOrder()
	lbl.Parent = scroll
	return lbl
end

local function divider()
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 1)
	f.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	f.BorderSizePixel = 0
	f.LayoutOrder = nextOrder()
	f.Parent = scroll
	return f
end

local function textBox(placeholder, height, multi)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, height or 28)
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	box.TextColor3 = Color3.fromRGB(240, 240, 240)
	box.Text = ""
	box.PlaceholderText = placeholder or ""
	box.PlaceholderColor3 = Color3.fromRGB(110, 110, 110)
	box.Font = Enum.Font.SourceSans
	box.TextSize = 14
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	box.MultiLine = multi == true
	box.TextWrapped = multi == true
	box.LayoutOrder = nextOrder()
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.PaddingTop = UDim.new(0, 4)
	p.PaddingBottom = UDim.new(0, 4)
	p.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 60)
	stroke.Parent = box
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = box
	box.Parent = scroll
	return box
end

local function button(text, color)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3 = color or Color3.fromRGB(70, 100, 200)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.SourceSansSemibold
	btn.TextSize = 14
	btn.Text = text
	btn.AutoButtonColor = true
	btn.LayoutOrder = nextOrder()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn
	btn.Parent = scroll
	return btn
end

local KEY_MASK = "••••••••••••••••"

local function wireMaskedKey(box, getter)
	box.Text = getter() ~= "" and KEY_MASK or ""
	box.Focused:Connect(function()
		if box.Text == KEY_MASK then
			box.Text = ""
		end
	end)
	box.FocusLost:Connect(function()
		if box.Text == "" and getter() ~= "" then
			box.Text = KEY_MASK
		end
	end)
end

-- ====== Settings: fal ======
header("fal API key")
muted("Stored locally via plugin:SetSetting (plaintext on disk). BYO key only.")
local keyBox = textBox("Paste your fal API key…", 28, false)
wireMaskedKey(keyBox, getKey)
local saveKeyBtn = button("Save fal key", Color3.fromRGB(60, 130, 90))

divider()

-- ====== Text-to-3D ======
header("Text → 3D")
local promptBox = textBox("e.g. a wooden treasure chest with iron bands", 64, true)
local genTextBtn = button("Generate from text")

divider()

-- ====== Image-to-3D ======
header("Image → 3D")
local pickedLabel = muted("(no image selected)", 18)
local pickBtn = button("Pick image from disk…", Color3.fromRGB(80, 80, 90))
local genImageBtn = button("Generate from image")

divider()

-- ====== Status ======
header("Status")
local statusBox = Instance.new("TextLabel")
statusBox.Size = UDim2.new(1, 0, 0, 140)
statusBox.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
statusBox.TextColor3 = Color3.fromRGB(200, 200, 200)
statusBox.Font = Enum.Font.Code
statusBox.TextSize = 12
statusBox.TextXAlignment = Enum.TextXAlignment.Left
statusBox.TextYAlignment = Enum.TextYAlignment.Top
statusBox.TextWrapped = true
statusBox.Text = "Idle."
statusBox.LayoutOrder = nextOrder()
statusBox.RichText = false
do
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 6)
	p.PaddingBottom = UDim.new(0, 6)
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.Parent = statusBox
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = statusBox
end
statusBox.Parent = scroll

local function setStatus(text)
	statusBox.Text = text
	print("[falgen] " .. text)
end
local function appendStatus(text)
	statusBox.Text = statusBox.Text .. "\n" .. text
	print("[falgen] " .. text)
end

local lastGlbUrl = nil
local urlBox = textBox("(GLB URL will appear here on completion — copy + use Studio's 3D Importer if auto-import fails)", 28, false)
urlBox.TextEditable = false
urlBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)

-- ============================================================
-- Wire-up
-- ============================================================
saveKeyBtn.MouseButton1Click:Connect(function()
	local typed = keyBox.Text
	if typed == "" or typed == KEY_MASK then
		setStatus(getKey() ~= "" and "Key unchanged." or "Paste a key first.")
		return
	end
	setKey(typed)
	keyBox.Text = KEY_MASK
	setStatus("fal key saved.")
end)

local pickedImageUrl = nil
local pickedFileName = nil

pickBtn.MouseButton1Click:Connect(function()
	if getKey() == "" then
		setStatus("Save your fal API key first (needed to upload the image).")
		return
	end
	local file = StudioService:PromptImportFile({ "png", "jpg", "jpeg", "webp" })
	if not file then
		setStatus("No file picked.")
		return
	end
	local ok, bytes = pcall(function()
		return file:GetBinaryContents()
	end)
	if not ok then
		setStatus("Couldn't read file: " .. tostring(bytes))
		return
	end
	local size = #bytes
	if size > MAX_IMAGE_BYTES then
		setStatus(string.format("Image is %.1f MB — please pick something under %d MB.", size / 1024 / 1024, MAX_IMAGE_BYTES / 1024 / 1024))
		return
	end
	local lower = string.lower(file.Name)
	local mime = "image/png"
	if string.match(lower, "%.jpe?g$") then
		mime = "image/jpeg"
	elseif string.match(lower, "%.webp$") then
		mime = "image/webp"
	end

	pickedFileName = file.Name
	pickedImageUrl = nil
	pickedLabel.Text = string.format("uploading %s (%.1f KB) to fal storage…", file.Name, size / 1024)
	pickedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)

	task.spawn(function()
		local upOk, urlOrErr = pcall(falStorageUpload, bytes, file.Name, mime)
		if not upOk then
			pickedLabel.Text = "upload failed: " .. tostring(urlOrErr)
			pickedLabel.TextColor3 = Color3.fromRGB(220, 100, 100)
			setStatus("Image upload failed. " .. tostring(urlOrErr))
			return
		end
		pickedImageUrl = urlOrErr
		pickedLabel.Text = string.format("✓ %s — uploaded", file.Name)
		pickedLabel.TextColor3 = Color3.fromRGB(120, 220, 120)
		setStatus("Image ready: " .. urlOrErr)
	end)
end)

local function setBusy(busy)
	genTextBtn.AutoButtonColor = not busy
	genImageBtn.AutoButtonColor = not busy
	genTextBtn.Active = not busy
	genImageBtn.Active = not busy
	genTextBtn.BackgroundColor3 = busy and Color3.fromRGB(50, 60, 100) or Color3.fromRGB(70, 100, 200)
	genImageBtn.BackgroundColor3 = busy and Color3.fromRGB(50, 60, 100) or Color3.fromRGB(70, 100, 200)
end

local function runJob(model, payload, label)
	setBusy(true)
	setStatus(string.format("Submitting %s…", label))
	local ok, result = pcall(falRunJob, model, payload, appendStatus)
	if not ok then
		appendStatus("Error: " .. tostring(result))
		setBusy(false)
		return
	end
	appendStatus("Job complete.")
	local glbUrl = extractGlbUrl(result)
	if not glbUrl then
		appendStatus("No GLB URL in response: " .. HttpService:JSONEncode(result))
		setBusy(false)
		return
	end
	lastGlbUrl = glbUrl
	urlBox.Text = glbUrl
	appendStatus("GLB ready! Copy the URL above, paste in your browser to download, then drag the .glb file onto Studio's viewport to import.")
	setBusy(false)
end

genTextBtn.MouseButton1Click:Connect(function()
	local prompt = promptBox.Text
	if prompt == "" or prompt == nil then
		setStatus("Enter a prompt first.")
		return
	end
	if getKey() == "" then
		setStatus("Save your fal API key first.")
		return
	end
	task.spawn(runJob, TEXT_MODEL, {
		prompt = prompt,
		face_limit = DEFAULT_FACE_LIMIT,
		texture = true,
	}, "text-to-3D")
end)

genImageBtn.MouseButton1Click:Connect(function()
	if not pickedImageUrl then
		setStatus("Pick an image first (and wait for upload to finish).")
		return
	end
	if getKey() == "" then
		setStatus("Save your fal API key first.")
		return
	end
	task.spawn(runJob, IMAGE_MODEL, {
		image_url = pickedImageUrl,
		face_limit = DEFAULT_FACE_LIMIT,
		texture = true,
	}, "image-to-3D (" .. (pickedFileName or "?") .. ")")
end)

print("[falgen] loaded. Click the 'falgen' button in the Plugins toolbar.")
