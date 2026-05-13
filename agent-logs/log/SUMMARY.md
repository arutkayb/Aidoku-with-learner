# Project Log

## Timeline

### 2026-05-12

- **Planned** Rebrand to "Aidoku Lingo": app identity rename (display + bundle id + URL scheme + PRODUCT_NAME + xcodeproj), app-icon swap from `~/Downloads/AppIcons`, README rewrite framing the fork, strip upstream artifacts (AltStore/FUNDING/issue templates/About-screen Discord+KoFi), local-folder + GitHub repo rename → [agent-logs/plans/20260512-135826_rebrand-aidoku-lingo/](../plans/20260512-135826_rebrand-aidoku-lingo/)
  - 5 tasks, 24 total steps
  - Tasks 1, 2, 3, 4 are independent and parallelizable; Task 5 (destructive folder + remote rename) depends on all
  - User-action step inside Task 5: parent-directory `mv` runs after Xcode is closed

- **Planned** Learner bug-fix batch: tri-state per-manga gate, zoom-aware overlay, Live Text coexistence, vocab punctuation cleanup, vocab edit UI, sentence focus + re-OCR, OCR language options → [agent-logs/plans/20260512-081402_learner-bugfix-batch/](../plans/20260512-081402_learner-bugfix-batch/)
  - 7 tasks, 36 total steps
  - Independent starting tasks: 1, 2, 4, 7 (no dependencies)
  - 3 depends on 2 (gesture-delegate ordering); 5 depends on 4 (normalize before edit); 6 depends on 2 (overlay rebuild)

### 2026-05-09

- **Planned** Mangadict MVP: Aidoku fork adding OCR + tap-to-translate + vocab list + minimal flashcards for German manga reading on iPad → [agent-logs/plans/20260509-123140_mangadict-mvp/](../plans/20260509-123140_mangadict-mvp/)
  - 8 tasks, 53 total steps
  - Critical path: Task 1 (OCR validation spike, kill switch) → Task 4 (OCR service) → Task 5 (reader overlay) → Task 6 (word lookup sheet) → ship
  - Tasks 2, 3, 4 can run in parallel after Task 1 verdict is GO
  - Task 8 (vocab list + flashcards) parallelizes with Tasks 5, 6, 7 once Tasks 2 + 3 are done
