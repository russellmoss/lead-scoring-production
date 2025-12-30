# =============================================================================
# EXECUTION LOGGER MODULE
# =============================================================================
# Location: C:\Users\russe\Documents\Lead Scoring\Version-3\utils\execution_logger.py
"""
Execution Logger for Lead Scoring Model Development

This module provides consistent logging across all phases of model development.
Each phase should use this logger to append entries to EXECUTION_LOG.md.

Usage:
    from utils.execution_logger import ExecutionLogger
    
    logger = ExecutionLogger()
    logger.start_phase("1.1", "Feature Engineering")
    
    # ... do work ...
    
    logger.log_file_created("features.csv", "Version-3/data/features.csv", "Training features")
    logger.log_validation_gate("G1.1.1", "PIT Integrity", True, "Zero leakage detected")
    logger.log_metric("Total Leads", 45000)
    logger.log_learning("Conversion rate is higher in 2025 (4.37%) vs 2024 (3.96%)")
    logger.log_decision("Using 60-day test window", "Provides sufficient test samples while maximizing training data")
    
    logger.end_phase(status="PASSED", next_steps=["Proceed to Phase 1.2"])
"""

import os
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional

class ExecutionLogger:
    def __init__(self, 
                 log_path: str = r"C:\Users\russe\Documents\Lead Scoring\Version-3\EXECUTION_LOG.md",
                 version: str = "v3"):
        """
        Initialize the execution logger.
        
        Args:
            log_path: Path to the execution log file
            version: Model version being developed
        """
        self.log_path = Path(log_path)
        self.version = version
        self.current_phase = None
        self.phase_start_time = None
        self.files_created = []
        self.validation_gates = []
        self.metrics = {}
        self.learnings = []
        self.decisions = []
        
        # Ensure directory exists
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize log file if it doesn't exist
        if not self.log_path.exists():
            self._initialize_log()
    
    def _initialize_log(self):
        """Create the initial log file with header."""
        header = f"""# Lead Scoring Model Execution Log

**Model Version:** {self.version}
**Started:** {datetime.now().strftime('%Y-%m-%d %H:%M')}
**Base Directory:** `C:\\Users\\russe\\Documents\\Lead Scoring\\Version-3`

---

## Execution Summary

| Phase | Status | Duration | Key Outcome |
|-------|--------|----------|-------------|

---

## Detailed Phase Logs

"""
        with open(self.log_path, 'w', encoding='utf-8') as f:
            f.write(header)
        
        print(f"[LOG] Initialized execution log: {self.log_path}")
    
    def start_phase(self, phase_id: str, phase_name: str):
        """
        Start logging a new phase.
        
        Args:
            phase_id: Phase identifier (e.g., "1.1", "0.0")
            phase_name: Human-readable phase name
        """
        self.current_phase = f"{phase_id}: {phase_name}"
        self.phase_start_time = datetime.now()
        self.files_created = []
        self.validation_gates = []
        self.metrics = {}
        self.learnings = []
        self.decisions = []
        self.actions = []
        
        print(f"\n{'='*60}")
        print(f"[START] Phase {self.current_phase}")
        print(f"   Time: {self.phase_start_time.strftime('%Y-%m-%d %H:%M')}")
        print('='*60)
    
    def log_file_created(self, filename: str, filepath: str, purpose: str):
        """Log a file that was created during this phase."""
        self.files_created.append({
            'filename': filename,
            'filepath': filepath,
            'purpose': purpose
        })
        print(f"   [FILE] Created: {filepath}")
    
    def log_validation_gate(self, gate_id: str, check: str, passed: bool, notes: str = ""):
        """Log a validation gate result."""
        status = "✅ PASSED" if passed else "❌ FAILED"
        self.validation_gates.append({
            'gate_id': gate_id,
            'check': check,
            'passed': passed,
            'status': status,
            'notes': notes
        })
        status_marker = "[PASS]" if passed else "[FAIL]"
        print(f"   {status_marker} {gate_id}: {check} - {notes}")
    
    def log_metric(self, name: str, value: Any):
        """Log a key metric from this phase."""
        self.metrics[name] = value
        print(f"   [METRIC] {name}: {value}")
    
    def log_learning(self, learning: str):
        """Log an insight or learning from this phase."""
        self.learnings.append(learning)
        print(f"   [LEARN] Learning: {learning}")
    
    def log_decision(self, decision: str, rationale: str):
        """Log a decision made during this phase."""
        self.decisions.append({
            'decision': decision,
            'rationale': rationale
        })
        print(f"   [DECISION] Decision: {decision}")
    
    def log_action(self, action: str):
        """Log an action taken (for the 'What We Did' section)."""
        if not hasattr(self, 'actions'):
            self.actions = []
        self.actions.append(action)
        print(f"   [ACTION] {action}")
    
    def end_phase(self, 
                  status: str = "PASSED",
                  next_steps: List[str] = None,
                  additional_notes: str = ""):
        """
        End the current phase and write to log.
        
        Args:
            status: "PASSED", "PASSED WITH WARNINGS", or "FAILED"
            next_steps: List of next steps for following phases
            additional_notes: Any additional notes to include
        """
        if not self.current_phase:
            raise ValueError("No phase started. Call start_phase() first.")
        
        end_time = datetime.now()
        duration_minutes = (end_time - self.phase_start_time).total_seconds() / 60
        
        # Determine status emoji
        status_emoji = "✅" if status == "PASSED" else ("⚠️" if "WARNING" in status else "❌")
        
        # Build the log entry
        entry = f"""
---

## Phase {self.current_phase}

**Executed:** {self.phase_start_time.strftime('%Y-%m-%d %H:%M')}
**Duration:** {duration_minutes:.1f} minutes
**Status:** {status_emoji} {status}

### What We Did
"""
        # Add actions
        if hasattr(self, 'actions') and self.actions:
            for action in self.actions:
                entry += f"- {action}\n"
        else:
            entry += "- [No actions logged]\n"
        
        # Add files created
        entry += "\n### Files Created\n"
        if self.files_created:
            entry += "| File | Path | Purpose |\n|------|------|---------|"
            for f in self.files_created:
                entry += f"\n| {f['filename']} | `{f['filepath']}` | {f['purpose']} |"
            entry += "\n"
        else:
            entry += "*No files created in this phase*\n"
        
        # Add validation gates
        entry += "\n### Validation Gates\n"
        if self.validation_gates:
            entry += "| Gate ID | Check | Result | Notes |\n|---------|-------|--------|-------|"
            for g in self.validation_gates:
                entry += f"\n| {g['gate_id']} | {g['check']} | {g['status']} | {g['notes']} |"
            entry += "\n"
        else:
            entry += "*No validation gates in this phase*\n"
        
        # Add metrics
        entry += "\n### Key Metrics\n"
        if self.metrics:
            for name, value in self.metrics.items():
                entry += f"- **{name}:** {value}\n"
        else:
            entry += "*No metrics logged*\n"
        
        # Add learnings
        entry += "\n### What We Learned\n"
        if self.learnings:
            for learning in self.learnings:
                entry += f"- {learning}\n"
        else:
            entry += "*No specific learnings logged*\n"
        
        # Add decisions
        entry += "\n### Decisions Made\n"
        if self.decisions:
            for d in self.decisions:
                entry += f"- **{d['decision']}** — {d['rationale']}\n"
        else:
            entry += "*No decisions logged*\n"
        
        # Add additional notes
        if additional_notes:
            entry += f"\n### Additional Notes\n{additional_notes}\n"
        
        # Add next steps
        entry += "\n### Next Steps\n"
        if next_steps:
            for step in next_steps:
                entry += f"- {step}\n"
        else:
            entry += "- Proceed to next phase\n"
        
        entry += "\n---\n"
        
        # Append to log file
        with open(self.log_path, 'a', encoding='utf-8') as f:
            f.write(entry)
        
        # Update summary table (read, find table, update)
        self._update_summary_table(status, duration_minutes)
        
        print(f"\n{'='*60}")
        print(f"[COMPLETE] Phase {self.current_phase}")
        print(f"   Status: {status}")
        print(f"   Duration: {duration_minutes:.1f} minutes")
        print(f"   Log updated: {self.log_path}")
        print('='*60 + "\n")
        
        # Reset for next phase
        self.current_phase = None
        self.phase_start_time = None
        self.actions = []
    
    def _update_summary_table(self, status: str, duration: float):
        """Update the summary table at the top of the log."""
        # Read current log
        with open(self.log_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Find the summary table and add a row
        table_marker = "| Phase | Status | Duration | Key Outcome |"
        if table_marker in content:
            # Determine key outcome from metrics or learnings
            if self.metrics:
                key_outcome = list(self.metrics.items())[0]
                outcome_str = f"{key_outcome[0]}: {key_outcome[1]}"
            elif self.learnings:
                outcome_str = self.learnings[0][:50] + "..."
            else:
                outcome_str = status
            
            status_emoji = "✅" if status == "PASSED" else ("⚠️" if "WARNING" in status else "❌")
            new_row = f"| {self.current_phase} | {status_emoji} {status} | {duration:.1f}m | {outcome_str} |"
            
            # Insert after the header row
            parts = content.split(table_marker)
            if len(parts) == 2:
                # Find the end of the table header row
                header_end = parts[1].find('\n')
                if header_end != -1:
                    # Insert the new row after the header separator row
                    rest = parts[1][header_end+1:]
                    separator_end = rest.find('\n')
                    if separator_end != -1:
                        new_content = parts[0] + table_marker + parts[1][:header_end+1] + rest[:separator_end+1] + new_row + "\n" + rest[separator_end+1:]
                        with open(self.log_path, 'w', encoding='utf-8') as f:
                            f.write(new_content)

