local LrProgressScope = import "LrProgressScope"

local ProgressDialog = {}

-- Create a new progress dialog for sync operations
-- Returns a progress object with methods to update, check cancellation, and close
function ProgressDialog.create(title)
    local progress = LrProgressScope({
        title = title,
    })

    local dialog = {
        scope = progress,
    }

    -- Update progress with current collection and counts
    function dialog:update(message, current, total)
        if self.scope:isCanceled() then
            return
        end
        self.scope:setPortionComplete(current, total)
        self.scope:setCaption(message)
    end

    -- Check if the user has requested cancellation
    function dialog:isCanceled()
        return self.scope:isCanceled()
    end

    -- Mark the progress as complete and close the dialog
    function dialog:done()
        self.scope:done()
    end

    return dialog
end

return ProgressDialog
