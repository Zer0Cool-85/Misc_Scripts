using System;
using System.ComponentModel;

namespace DeviceSetupUI {
    public sealed class StepViewModel : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(string name) {
            var handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
        public string Number { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public bool Animated { get; set; }
        public string Requirement { get; set; }
        public string SelectStepLabel { get; set; }
        private bool isSelected;
        public bool IsSelected { get { return isSelected; } set { if(isSelected != value) { isSelected = value; Changed("IsSelected"); } } }
        private bool showSelection;
        public bool ShowSelection { get { return showSelection; } set { if(showSelection != value) { showSelection = value; Changed("ShowSelection"); } } }
        private string status = "Pending";
        public string Status { get { return status; } set { if(status != value) { status = value; Changed("Status"); Changed("Badge"); } } }
        public string Badge { get { return status == "AlreadyComplete" ? "Already done" : status == "NotSelected" ? "Not selected" : status; } }
        private string detail = "Waiting to start";
        public string Detail { get { return detail; } set { if(detail != value) { detail = value; Changed("Detail"); } } }
        private string error = "";
        public string Error { get { return error; } set { if(error != value) { error = value; Changed("Error"); Changed("HasError"); } } }
        public bool HasError { get { return !String.IsNullOrWhiteSpace(error); } }
        private string elapsed = "";
        public string Elapsed { get { return elapsed; } set { if(elapsed != value) { elapsed = value; Changed("Elapsed"); } } }
        private double percent = -1;
        public double Percent { get { return percent; } set { if(percent != value) { percent = value; Changed("Percent"); Changed("HasPercent"); } } }
        public bool HasPercent { get { return percent >= 0 && status == "Running"; } }
        public void RefreshProgress() { Changed("HasPercent"); }
    }
}
