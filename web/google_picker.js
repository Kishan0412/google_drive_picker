// web/google_picker.js
// Requires (in index.html): apis.google.com/js/api.js and accounts.google.com/gsi/client

let pickerApiLoaded = false;

// ── OAuth token via Google Identity Services ────────────────────────────────
// Last arg is always the Flutter callback name; it receives a JSON string or null.
function requestDriveToken(clientId, scope, callbackName) {
  let done = false;
  const finish = (value) => {
    if (done) return;
    done = true;
    window[callbackName](value);
  };

  try {
    const client = google.accounts.oauth2.initTokenClient({
      client_id: clientId,
      scope: scope,
      callback: (resp) => {
        if (resp.error || !resp.access_token) {
          finish(null);
        } else {
          finish(JSON.stringify({ token: resp.access_token, expiresIn: resp.expires_in }));
        }
      },
      error_callback: () => finish(null), // popup closed / blocked
    });
    // prompt: '' => no consent screen again if the user already granted access
    client.requestAccessToken({ prompt: '' });
  } catch (e) {
    console.error('requestDriveToken failed', e);
    finish(null);
  }
}

// ── Google Picker ───────────────────────────────────────────────────────────
function loadPicker(accessToken, clientId, appId, allowMultiple, initialQuery, callbackName) {
  const show = () => createPicker(accessToken, appId, allowMultiple, initialQuery, callbackName);

  if (pickerApiLoaded) {
    show();
  } else {
    gapi.load('picker', () => {
      pickerApiLoaded = true;
      show();
    });
  }
}

function createPicker(accessToken, appId, allowMultiple, initialQuery, callbackName) {
  const view = new google.picker.DocsView()
    .setIncludeFolders(false)
    .setSelectFolderEnabled(false);

  // Pre-filter the picker's own search. The picker UI already has a search box.
  if (initialQuery) view.setQuery(initialQuery);

  const builder = new google.picker.PickerBuilder()
    .setAppId(appId)
    .setOAuthToken(accessToken)
    .addView(view)
    .addView(new google.picker.DocsUploadView())
    .setDeveloperKey('Add-New-crendential-after-select google picker and drive service')
    .setCallback((data) => pickerCallback(data, callbackName));

  if (allowMultiple) {
    builder.enableFeature(google.picker.Feature.MULTISELECT_ENABLED);
  }

  builder.build().setVisible(true);
}

function pickerCallback(data, callbackName) {
  const action = data[google.picker.Response.ACTION];

  if (action === google.picker.Action.PICKED) {
    const files = data[google.picker.Response.DOCUMENTS].map((file) => ({
      id: file[google.picker.Document.ID],
      name: file[google.picker.Document.NAME],
      mimeType: file[google.picker.Document.MIME_TYPE],
      url: file[google.picker.Document.URL],
      sizeBytes: file[google.picker.Document.SIZE_BYTES],
    }));
    window[callbackName](JSON.stringify(files));
  } else if (action === google.picker.Action.CANCEL) {
    window[callbackName](null);
  }
  // LOADED action: ignore
}