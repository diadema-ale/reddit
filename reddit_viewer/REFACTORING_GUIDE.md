# RedditViewer Refactoring Guide

## Overview
This guide outlines the refactoring plan to improve code maintainability by:
1. Extracting repeated UI components into reusable modules
2. Breaking down large files into smaller, focused components
3. Improving code organization and reducing duplication

## Current State Analysis

### Large Files Identified
- `reddit_live.ex` - 669 lines (handles too many responsibilities)
- `reddit_live.html.heex` - 673 lines (contains multiple extractable components)
- `post_processor.ex` - 275 lines (reasonably sized but could be split)
- `home.html.heex` - 244 lines (has duplicate components with live view)

### Repeated Components Found
1. **Ticker Badges** - Used in multiple places with direction-based coloring
2. **AI Processing Status** - Shows processing/failed/success states
3. **Data Tables** - Posts table and ticker stats table share similar structure
4. **Progress Indicators** - Fetch progress display
5. **Performance Summary** - Pitch performance statistics table

## Refactoring Plan

### Phase 1: Extract UI Components to `/components/ui/`

#### 1.1 Ticker Badge Component (`ticker_badge.ex`)
- [x] Already exists as `flair_badge.ex`
- [ ] Create a more generic `ticker_badge.ex` for ticker symbols
- Attributes: `ticker`, `direction` (long/short/neutral)
- Handles color logic based on direction

**Current duplication found in:**
- `reddit_live.html.heex` lines 123-137, 464-478
- Badge color logic repeated 3+ times

**Example usage after extraction:**
```heex
<UI.TickerBadge ticker="AAPL" direction="long" />
```

#### 1.2 AI Processing Status (`ai_status.ex`)
- [ ] Extract from posts table
- Shows: Processing (spinner), Failed (error), Success (ticker display)
- Attributes: `status`, `error`, `tickers`, `direction`

**Current duplication found in:**
- `reddit_live.html.heex` lines 446-483 (posts table)
- `home.html.heex` lines 186-221
- Complex conditional rendering repeated

**Example usage after extraction:**
```heex
<UI.AIStatus 
  processing_error={post.ai_processing_error}
  processed_at={post.ai_processed_at}
  tickers={post.ticker_symbols}
  direction={post.ticker_direction}
/>
```

#### 1.3 Data Table Component (`data_table.ex`)
- [ ] Create generic table component
- Configurable columns, row rendering
- Built-in sorting, pagination support
- Reduce duplication between posts and ticker tables

**Current duplication found in:**
- Posts table: `reddit_live.html.heex` lines 381-510
- Ticker stats table: `reddit_live.html.heex` lines 524-666
- Similar structure in `home.html.heex` lines 131-241

**Example usage after extraction:**
```heex
<UI.DataTable 
  id="posts-table"
  rows={@user_posts}
  columns={[
    %{key: :subreddit, label: "Subreddit", format: &("r/#{&1}")},
    %{key: :title, label: "Title", class: "w-80", truncate: true},
    %{key: :ticker_symbols, label: "Ticker", component: &UI.AIStatus/1}
  ]}
/>
```

#### 1.4 Progress Bar (`progress_bar.ex`)
- [ ] Extract fetch progress display
- Attributes: `status`, `message`, `count`, `date_range`
- Handles different states: fetching, complete, error

#### 1.5 Performance Summary Table (`performance_summary.ex`)
- [ ] Extract pitch summary table
- Self-contained component with stats calculation
- Attributes: `pitch_summary`

### Phase 2: Extract Functional Components to `/components/functional/`

#### 2.1 From `reddit_live.ex`:

##### Ticker Stats Builder (`ticker_stats_builder.ex`)
- [ ] Extract `build_ticker_stats/1` function (lines 334-403)
- [ ] Extract `enrich_ticker_with_prices/1` function (lines 405-471)
- Handles grouping posts by ticker and price fetching

**Current size:** 138+ lines of ticker logic in LiveView
**Benefits:** Testable in isolation, reusable for other views

##### Pitch Summary Builder (`pitch_summary_builder.ex`)
- [ ] Extract `build_pitch_summary/2` function (lines 473-667)
- Calculates performance metrics and success rates

**Current size:** 194+ lines of complex calculation logic
**Benefits:** Can be tested separately, reduces LiveView complexity

#### 2.2 From `post_processor.ex`:

##### Cache Manager (`cache_manager.ex`)
- [ ] Extract caching logic
- Handles post retrieval and storage

##### AI Enrichment (`ai_enrichment.ex`)
- [ ] Extract `enrich_post_with_ai/1` and related functions
- Manages AI processing pipeline

### Phase 3: Create Shared Components

#### 3.1 Status Badge (`status_badge.ex`)
- [ ] Generic badge component for various statuses
- Configurable colors and icons
- Replace direction badges, status indicators

#### 3.2 Loading Indicator (`loading_indicator.ex`)
- [ ] Reusable loading states
- Different sizes and styles
- With optional text

#### 3.3 Empty State (`empty_state.ex`)
- [ ] Component for when no data is available
- Configurable message and icon

## Implementation Order

1. **Week 1**: Extract UI components (Phase 1)
   - Start with most reused: `ai_status.ex`, `ticker_badge.ex`
   - Then tables: `data_table.ex`, `performance_summary.ex`

2. **Week 2**: Extract functional components (Phase 2)
   - Move business logic out of LiveView
   - Create focused modules for specific tasks

3. **Week 3**: Create shared components and refactor (Phase 3)
   - Replace existing implementations with new components
   - Clean up and test

## Progress Tracker

### UI Components
- [ ] `ticker_badge.ex` - For ticker symbols with direction
- [ ] `ai_status.ex` - AI processing status display
- [ ] `data_table.ex` - Generic configurable table
- [ ] `progress_bar.ex` - Fetch progress indicator
- [ ] `performance_summary.ex` - Pitch performance table

### Functional Components
- [ ] `ticker_stats_builder.ex` - Ticker statistics logic
- [ ] `pitch_summary_builder.ex` - Pitch summary calculations
- [ ] `cache_manager.ex` - Post caching logic
- [ ] `ai_enrichment.ex` - AI processing pipeline

### Shared Components
- [ ] `status_badge.ex` - Generic status badges
- [ ] `loading_indicator.ex` - Loading states
- [ ] `empty_state.ex` - No data display

### File Size Reduction
- [ ] `reddit_live.ex` - Target: <400 lines (from 669)
- [ ] `reddit_live.html.heex` - Target: <300 lines (from 673)
- [ ] `post_processor.ex` - Target: <150 lines (from 275)

## Benefits
1. **Improved Maintainability**: Smaller, focused files are easier to understand
2. **Reduced Duplication**: Shared components eliminate repeated code
3. **Better Testing**: Isolated components are easier to test
4. **Faster Development**: Reusable components speed up new feature development

## Expected Improvements

### Before vs After Metrics
| File | Current Lines | Target Lines | Reduction |
|------|---------------|--------------|-----------|
| `reddit_live.ex` | 669 | ~350 | 48% |
| `reddit_live.html.heex` | 673 | ~250 | 63% |
| `post_processor.ex` | 275 | ~150 | 45% |
| `home.html.heex` | 244 | ~100 | 59% |

### Code Duplication Reduction
- Ticker badge logic: From 5+ occurrences to 1 component
- AI status display: From 3+ occurrences to 1 component
- Table structures: From 3 similar implementations to 1 configurable component

## Best Practices for Refactoring

1. **Component Design**
   - Follow Phoenix.Component patterns
   - Use proper attr definitions with types and docs
   - Include default values where appropriate
   - Make components as generic as reasonable

2. **Testing Strategy**
   - Write tests for each extracted component
   - Test edge cases and error states
   - Ensure performance isn't degraded

3. **Migration Approach**
   - Extract one component at a time
   - Update all usages before moving to next
   - Run tests after each extraction
   - Keep commits focused and atomic

4. **Documentation**
   - Add @moduledoc for each new module
   - Include usage examples
   - Document any complex logic
   - Update this guide as you progress

## Notes
- All new components should follow Phoenix component patterns
- Include proper documentation with examples
- Write tests for extracted components
- Consider performance implications of component boundaries
- Use `mix format` and `mix credo` after each change
- Run `mix test` to ensure nothing breaks
