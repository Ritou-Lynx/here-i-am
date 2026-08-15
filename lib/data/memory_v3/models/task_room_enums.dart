/// Enums for TaskRooms schema.
///
/// These enums define allowed values for task types, statuses, artifact types,
/// and decision types in the TaskRooms domain.

/// Task type categories.
enum TaskType {
  /// Software development tasks
  coding('coding'),

  /// Research and investigation tasks
  research('research'),

  /// Debugging and troubleshooting tasks
  debugging('debugging'),

  /// Planning and design tasks
  planning('planning'),

  /// Content generation tasks (articles, documents, cards)
  contentGeneration('content_generation'),

  /// Media processing tasks (image, video analysis)
  media('media'),

  /// Whiteboard canvas operations
  whiteboard('whiteboard'),

  /// Link ingestion and card creation
  linkIngestion('link_ingestion'),

  /// Other task types
  other('other');

  const TaskType(this.value);
  final String value;

  static TaskType fromString(String value) {
    return TaskType.values.firstWhere((e) => e.value == value);
  }
}

/// Task status lifecycle states.
enum TaskStatus {
  /// Task is planned but not yet started
  pending('pending'),

  /// Task is actively being worked on
  running('running'),

  /// Task is paused or blocked
  blocked('blocked'),

  /// Task is waiting for user decision
  waitingForUser('waiting_for_user'),

  /// Task has been completed successfully
  completed('completed'),

  /// Task has failed with errors
  failed('failed'),

  /// Task has been cancelled or abandoned
  cancelled('cancelled'),

  /// Task has been archived (soft delete)
  archived('archived');

  const TaskStatus(this.value);
  final String value;

  static TaskStatus fromString(String value) {
    return TaskStatus.values.firstWhere((e) => e.value == value);
  }

  /// Check if this status is terminal (task is finished).
  bool get isTerminal {
    return this == TaskStatus.completed ||
        this == TaskStatus.failed ||
        this == TaskStatus.cancelled ||
        this == TaskStatus.archived;
  }

  /// Valid state transitions.
  static const Map<TaskStatus, Set<TaskStatus>> validTransitions = {
    TaskStatus.pending: {
      TaskStatus.running,
      TaskStatus.cancelled,
      TaskStatus.archived,
    },
    TaskStatus.running: {
      TaskStatus.blocked,
      TaskStatus.waitingForUser,
      TaskStatus.completed,
      TaskStatus.failed,
      TaskStatus.cancelled,
      TaskStatus.archived,
    },
    TaskStatus.blocked: {
      TaskStatus.running,
      TaskStatus.cancelled,
      TaskStatus.archived,
    },
    TaskStatus.waitingForUser: {
      TaskStatus.running,
      TaskStatus.cancelled,
      TaskStatus.archived,
    },
    TaskStatus.completed: {
      TaskStatus.archived,
    },
    TaskStatus.failed: {
      TaskStatus.archived,
    },
    TaskStatus.cancelled: {
      TaskStatus.archived,
    },
    TaskStatus.archived: {
      // Archived is terminal - no transitions allowed
    },
  };

  /// Check if transition to [newStatus] is valid.
  bool canTransitionTo(TaskStatus newStatus) {
    return validTransitions[this]?.contains(newStatus) ?? false;
  }
}

/// Artifact type categories.
enum ArtifactType {
  /// Code changes (diffs, patches)
  codeDiff('code_diff'),

  /// Analysis results (profiling, metrics)
  analysisResult('analysis_result'),

  /// Error logs and stack traces
  errorLog('error_log'),

  /// Test results
  testResult('test_result'),

  /// Screenshots or screen recordings
  screenshot('screenshot'),

  /// Design mockups or wireframes
  designMockup('design_mockup'),

  /// Documentation
  documentation('documentation'),

  /// Other artifact types
  other('other');

  const ArtifactType(this.value);
  final String value;

  static ArtifactType fromString(String value) {
    return ArtifactType.values.firstWhere((e) => e.value == value);
  }
}

/// Decision status for task decisions.
enum DecisionStatus {
  /// Decision is pending user input
  pending('pending'),

  /// Decision has been resolved
  resolved('resolved'),

  /// Decision was cancelled
  cancelled('cancelled'),

  /// Decision was superseded by a newer one
  superseded('superseded');

  const DecisionStatus(this.value);
  final String value;

  static DecisionStatus fromString(String value) {
    return DecisionStatus.values.firstWhere((e) => e.value == value);
  }
}

/// Decision type categories.
enum DecisionType {
  /// Choosing between different approaches
  approachChoice('approach_choice'),

  /// Setting parameter values
  parameterValue('parameter_value'),

  /// Approval or rejection decisions
  approval('approval'),

  /// Prioritization decisions
  prioritization('prioritization'),

  /// Other decision types
  other('other');

  const DecisionType(this.value);
  final String value;

  static DecisionType fromString(String value) {
    return DecisionType.values.firstWhere((e) => e.value == value);
  }
}
