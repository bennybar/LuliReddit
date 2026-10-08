package com.bennybar.luli_for_reddit.feature.media

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.launch

private enum class FolderChoice { GALLERY, PICK }

/**
 * Settings row "Save media to": the gallery's Ilay album, or a folder the
 * user picks (Storage Access Framework). For the Settings screen.
 */
@Composable
fun MediaFolderSettingRow(modifier: Modifier = Modifier) {
    val folder by app.media.folder.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    ListItem(
        modifier = modifier.clickable {
            scope.launch {
                when (showFolderSheet(folder)) {
                    FolderChoice.GALLERY -> app.media.useGallery()
                    FolderChoice.PICK -> app.media.pickFolder()
                    null -> {}
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        leadingContent = { Icon(Icons.Rounded.Folder, null) },
        headlineContent = { Text("Save media to") },
        supportingContent = { Text(folder?.name ?: "Gallery (Ilay album)") },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showFolderSheet(folder: MediaFolder?): FolderChoice? = Overlays.show { done ->
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    fun pick(choice: FolderChoice) {
        scope.launch { state.hide() }.invokeOnCompletion { done(choice) }
    }
    ModalBottomSheet(onDismissRequest = { done(null) }, sheetState = state) {
        Column(Modifier.navigationBarsPadding().padding(bottom = 8.dp)) {
            ListItem(
                modifier = Modifier.clickable { pick(FolderChoice.GALLERY) },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                leadingContent = { Icon(Icons.Rounded.PhotoLibrary, null) },
                headlineContent = { Text("Gallery (Ilay album)") },
                trailingContent = { if (folder == null) Icon(Icons.Rounded.Check, null) },
            )
            ListItem(
                modifier = Modifier.clickable { pick(FolderChoice.PICK) },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                leadingContent = { Icon(Icons.Rounded.CreateNewFolder, null) },
                headlineContent = { Text(folder?.name ?: "Choose a folder…") },
                supportingContent = if (folder != null) ({ Text("Tap to change") }) else null,
                trailingContent = { if (folder != null) Icon(Icons.Rounded.Check, null) },
            )
        }
    }
}
